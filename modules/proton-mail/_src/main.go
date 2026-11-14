// proton-mail: Proton Mail custom domains and addresses as declared state.
//
// Proton has no public API for these, so this speaks the API its own clients
// use, through Proton's go-proton-api (the library Proton Bridge is built
// on), identifying itself honestly as kagamizo-proton-mail.
//
//	proton-mail login            sign in (password from the environment, the
//	                             2FA code from stdin), unlock the keys
//	proton-mail plan  <state>    declared domains and addresses against Proton
//	proton-mail apply <state>    add missing domains, create missing addresses
//	                             (with their keys), set catch-alls; --prune
//	                             disables addresses no longer declared
//	proton-mail domains          the live domains with their DNS states, JSON
//
// Every command but login runs from a saved session, PROTON_MAIL_SESSION
// (JSON: UID, RefreshToken, KeyPass). Proton rotates the refresh token on use,
// so each run writes the new session to file descriptor 3 for the caller to
// store; nothing secret is ever printed.
package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"sort"
	"strings"

	"github.com/ProtonMail/go-proton-api"
	"github.com/ProtonMail/gopenpgp/v2/crypto"
)

const (
	hostURL    = proton.DefaultHostURL
	appVersion = "other-kagamizo-proton-mail@0.1.0"
)

type session struct {
	UID          string
	RefreshToken string
	KeyPass      []byte
}

// The declared state, rendered from the identity model by the Nix wrapper.
type state struct {
	Domains map[string]struct {
		// Mailboxes: local part -> display name.
		Addresses map[string]string
		// Local part of the address that receives mail to undeclared ones.
		CatchAll string
		// What the repo declares for the domain's DNS, to tell whether it
		// still matches what Proton asks for.
		Declared *struct {
			Verification string
			DkimID       string
		}
	}
}

type domain struct {
	ID          string
	DomainName  string
	VerifyCode  string
	State       int
	VerifyState int
	MxState     int
	SpfState    int
	DmarcState  int
	DKIM        struct {
		State  int
		Config []struct{ Hostname, CNAME string }
	}
	CatchAll string `json:",omitempty"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "proton-mail:", err)
		os.Exit(1)
	}
}

func run() error {
	usage := errors.New("usage: proton-mail <login | plan <state> | apply <state> [--prune] | domains>")
	if len(os.Args) < 2 {
		return usage
	}
	ctx := context.Background()
	m := proton.New(proton.WithHostURL(hostURL), proton.WithAppVersion(appVersion))
	defer m.Close()

	if os.Args[1] == "login" {
		return login(ctx, m)
	}

	a, err := resume(ctx, m)
	if err != nil {
		return err
	}
	defer a.c.Close()

	switch os.Args[1] {
	case "domains":
		ds, err := a.domains(ctx)
		if err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(ds)
	case "plan", "apply":
		if len(os.Args) < 3 {
			return usage
		}
		raw, err := os.ReadFile(os.Args[2])
		if err != nil {
			return err
		}
		var want state
		if err := json.Unmarshal(raw, &want); err != nil {
			return fmt.Errorf("state: %w", err)
		}
		prune := len(os.Args) > 3 && os.Args[3] == "--prune"
		return a.reconcile(ctx, want, os.Args[1] == "apply", prune)
	}
	return usage
}

// --- sessions -------------------------------------------------------------

func login(ctx context.Context, m *proton.Manager) error {
	user, pass := os.Getenv("PROTON_USERNAME"), os.Getenv("PROTON_PASSWORD")
	if user == "" || pass == "" {
		return errors.New("login needs PROTON_USERNAME and PROTON_PASSWORD (from secretspec)")
	}
	c, auth, err := m.NewClientWithLogin(ctx, user, []byte(pass))
	var apiErr *proton.APIError
	if errors.As(err, &apiErr) && apiErr.IsHVError() {
		// Human verification: a link for the owner to open, like any 2FA.
		hv, herr := apiErr.GetHVDetails()
		if herr != nil {
			return herr
		}
		fmt.Fprintf(os.Stderr, "Proton asks for human verification. Open, complete, then press Enter:\n  https://verify.proton.me/?methods=%s&token=%s\n",
			strings.Join(hv.Methods, ","), hv.Token)
		if _, err := bufio.NewReader(os.Stdin).ReadString('\n'); err != nil {
			return err
		}
		c, auth, err = m.NewClientWithLoginWithHVToken(ctx, user, []byte(pass), hv)
	}
	if err != nil {
		return fmt.Errorf("login: %w", err)
	}
	defer c.Close()

	if auth.TwoFA.Enabled&proton.HasTOTP != 0 {
		fmt.Fprintln(os.Stderr, "2FA code:")
		code, err := bufio.NewReader(os.Stdin).ReadString('\n')
		if err != nil {
			return err
		}
		if err := c.Auth2FA(ctx, proton.Auth2FAReq{TwoFactorCode: strings.TrimSpace(code)}); err != nil {
			return fmt.Errorf("2FA: %w", err)
		}
	} else if auth.TwoFA.Enabled != 0 {
		return errors.New("only a TOTP code is supported as the second factor")
	}

	u, err := c.GetUser(ctx)
	if err != nil {
		return err
	}
	salts, err := c.GetSalts(ctx)
	if err != nil {
		return err
	}
	keyPass, err := salts.SaltForKey([]byte(pass), u.Keys.Primary().ID)
	if err != nil {
		return err
	}
	if _, err := u.Keys.Unlock(keyPass, nil); err != nil {
		return fmt.Errorf("unlocking the account keys: %w", err)
	}
	fmt.Fprintf(os.Stderr, "signed in as %s\n", u.Email)
	return save(session{UID: auth.UID, RefreshToken: auth.RefreshToken, KeyPass: keyPass})
}

// save writes the session to fd 3, which the wrapper pipes into secretspec.
func save(s session) error {
	f := os.NewFile(3, "session")
	if f == nil {
		return errors.New("no file descriptor 3 to save the session to")
	}
	defer f.Close()
	return json.NewEncoder(f).Encode(s)
}

type api struct {
	c      *proton.Client
	uid    string
	access string
	userKR *crypto.KeyRing
	user   proton.User
}

func resume(ctx context.Context, m *proton.Manager) (*api, error) {
	var s session
	if err := json.Unmarshal([]byte(os.Getenv("PROTON_MAIL_SESSION")), &s); err != nil || s.UID == "" {
		return nil, errors.New("no session: run `proton-mail login` first")
	}
	c, auth, err := m.NewClientWithRefresh(ctx, s.UID, s.RefreshToken)
	if err != nil {
		return nil, fmt.Errorf("resuming the session (log in again): %w", err)
	}
	if err := save(session{UID: auth.UID, RefreshToken: auth.RefreshToken, KeyPass: s.KeyPass}); err != nil {
		return nil, err
	}
	u, err := c.GetUser(ctx)
	if err != nil {
		return nil, err
	}
	kr, err := u.Keys.Unlock(s.KeyPass, nil)
	if err != nil {
		return nil, fmt.Errorf("unlocking the account keys: %w", err)
	}
	return &api{c: c, uid: auth.UID, access: auth.AccessToken, userKR: kr, user: u}, nil
}

// do calls a route go-proton-api does not wrap, with the session's tokens.
func (a *api) do(ctx context.Context, method, path string, body, out any) error {
	var r io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return err
		}
		r = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, hostURL+path, r)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+a.access)
	req.Header.Set("x-pm-uid", a.uid)
	req.Header.Set("x-pm-appversion", appVersion)
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	raw, err := io.ReadAll(res.Body)
	if err != nil {
		return err
	}
	var e struct {
		Code  int
		Error string
	}
	_ = json.Unmarshal(raw, &e)
	if res.StatusCode >= 300 || (e.Code != 0 && e.Code != 1000 && e.Code != 1001) {
		return fmt.Errorf("%s %s: %d %s", method, path, e.Code, e.Error)
	}
	if out != nil {
		return json.Unmarshal(raw, out)
	}
	return nil
}

// --- domains and addresses ------------------------------------------------

func (a *api) domains(ctx context.Context) ([]domain, error) {
	var res struct{ Domains []domain }
	err := a.do(ctx, http.MethodGet, "/core/v4/domains?PageSize=100", nil, &res)
	return res.Domains, err
}

func (a *api) refresh(ctx context.Context, id string) (domain, error) {
	var res struct{ Domain domain }
	err := a.do(ctx, http.MethodGet, "/core/v4/domains/"+id+"?Refresh=1", nil, &res)
	return res.Domain, err
}

var dkimID = regexp.MustCompile(`^protonmail\d*\.domainkey\.([^.]+)\.domains\.proton\.ch\.?$`)

// What Proton asks the domain's DNS to carry, in the repo's terms.
func wantDNS(d domain) (verification, dkim string) {
	verification = strings.TrimPrefix(d.VerifyCode, "protonmail-verification=")
	for _, c := range d.DKIM.Config {
		if m := dkimID.FindStringSubmatch(c.CNAME); m != nil {
			return verification, m[1]
		}
	}
	return verification, ""
}

func good(d domain) string {
	mark := func(ok bool, what string) string {
		if ok {
			return what + " ok"
		}
		return what + " pending"
	}
	return strings.Join([]string{
		mark(d.VerifyState == 2, "verification"),
		mark(d.MxState == 3 || d.MxState == 4, "MX"),
		mark(d.SpfState == 3, "SPF"),
		mark(d.DKIM.State == 4, "DKIM"),
		mark(d.DmarcState == 3 || d.DmarcState == 4, "DMARC"),
	}, ", ")
}

func (a *api) reconcile(ctx context.Context, want state, apply, prune bool) error {
	live, err := a.domains(ctx)
	if err != nil {
		return err
	}
	byName := map[string]domain{}
	for _, d := range live {
		byName[strings.ToLower(d.DomainName)] = d
	}
	addrs, err := a.c.GetAddresses(ctx)
	if err != nil {
		return err
	}
	byEmail := map[string]proton.Address{}
	for _, ad := range addrs {
		byEmail[strings.ToLower(ad.Email)] = ad
	}

	names := make([]string, 0, len(want.Domains))
	for n := range want.Domains {
		names = append(names, n)
	}
	sort.Strings(names)

	for _, name := range names {
		w := want.Domains[name]
		d, ok := byName[name]
		if !ok {
			fmt.Printf("+ domain   %s\n", name)
			if !apply {
				continue
			}
			var res struct{ Domain domain }
			if err := a.do(ctx, http.MethodPost, "/core/v4/domains", map[string]any{"Name": name, "AllowedForMail": true}, &res); err != nil {
				return err
			}
			d = res.Domain
		} else if d, err = a.refresh(ctx, d.ID); err != nil {
			return err
		}

		v, k := wantDNS(d)
		if w.Declared == nil || w.Declared.Verification != v || w.Declared.DkimID != k {
			// Not secret, so it is declared in git and applied by OpenTofu.
			fmt.Printf("! declare  identity.domains.%q.proton = { verification = %q; dkimId = %q; };\n", name, v, k)
		}
		fmt.Printf("  dns      %s: %s\n", name, good(d))
		verified := d.State == 1

		locals := make([]string, 0, len(w.Addresses))
		for l := range w.Addresses {
			locals = append(locals, l)
		}
		sort.Strings(locals)
		for _, local := range locals {
			email := local + "@" + name
			if ad, ok := byEmail[email]; ok {
				state := "enabled"
				if ad.Status != proton.AddressStatusEnabled {
					state = "disabled"
				}
				fmt.Printf("  address  %s (%s)\n", email, state)
				continue
			}
			if !verified {
				fmt.Printf("+ address  %s (once %s is verified)\n", email, name)
				continue
			}
			fmt.Printf("+ address  %s\n", email)
			if apply {
				ad, err := a.createAddress(ctx, local, name, w.Addresses[local])
				if err != nil {
					return fmt.Errorf("%s: %w", email, err)
				}
				byEmail[email] = ad
			}
		}

		if w.CatchAll != "" && verified {
			target, ok := byEmail[w.CatchAll+"@"+name]
			switch {
			case !ok:
				fmt.Printf("  catchall %s -> %s@%s (once it exists)\n", name, w.CatchAll, name)
			case d.CatchAll == target.ID:
				fmt.Printf("  catchall %s -> %s\n", name, target.Email)
			default:
				fmt.Printf("~ catchall %s -> %s\n", name, target.Email)
				if apply {
					if err := a.do(ctx, http.MethodPut, "/core/v4/domains/"+d.ID+"/catchall", map[string]any{"AddressID": target.ID}, nil); err != nil {
						return err
					}
				}
			}
		}

		// Addresses on a declared domain that the repo no longer declares.
		for email, ad := range byEmail {
			local, dom, _ := strings.Cut(email, "@")
			if dom != name || ad.Status != proton.AddressStatusEnabled {
				continue
			}
			if _, declared := w.Addresses[local]; declared {
				continue
			}
			if apply && prune {
				if err := a.c.DisableAddress(ctx, ad.ID); err != nil {
					return err
				}
				fmt.Printf("- disabled %s\n", email)
			} else {
				fmt.Printf("- disable  %s (not declared; apply --prune)\n", email)
			}
		}
	}
	return nil
}

// createAddress creates the address and its first key the way Proton's web
// client does (createAddressKeyV2): a random token is the key's passphrase,
// encrypted and signed with the user key, and the address's signed key list
// names the new key as primary.
func (a *api) createAddress(ctx context.Context, local, domainName, displayName string) (proton.Address, error) {
	body := map[string]any{"Local": local, "Domain": domainName, "DisplayName": displayName}
	// On a plan with an organization the address belongs to your member;
	// a plan without one has no members and takes none.
	var me struct{ Member struct{ ID string } }
	if err := a.do(ctx, http.MethodGet, "/core/v4/members/me", nil, &me); err == nil && me.Member.ID != "" {
		body["MemberID"] = me.Member.ID
	}
	var res struct{ Address proton.Address }
	if err := a.do(ctx, http.MethodPost, "/core/v4/addresses", body, &res); err != nil {
		return proton.Address{}, err
	}
	addr := res.Address

	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return addr, err
	}
	token := []byte(hex.EncodeToString(raw))

	key, err := crypto.GenerateKey(addr.Email, addr.Email, "x25519", 0)
	if err != nil {
		return addr, err
	}
	locked, err := key.Lock(token)
	if err != nil {
		return addr, err
	}
	armored, err := locked.Armor()
	if err != nil {
		return addr, err
	}

	msg := crypto.NewPlainMessage(token)
	enc, err := a.userKR.Encrypt(msg, nil)
	if err != nil {
		return addr, err
	}
	encArm, err := enc.GetArmored()
	if err != nil {
		return addr, err
	}
	sig, err := a.userKR.SignDetached(msg)
	if err != nil {
		return addr, err
	}
	sigArm, err := sig.GetArmored()
	if err != nil {
		return addr, err
	}

	kr, err := crypto.NewKeyRing(key)
	if err != nil {
		return addr, err
	}
	fp := key.GetFingerprint()
	sha := key.GetSHA256Fingerprints()
	skl, err := proton.NewKeyList(kr, []proton.KeyListEntry{{
		Fingerprint:        fp,
		SHA256Fingerprints: sha,
		Flags:              proton.KeyStateTrusted | proton.KeyStateActive,
		Primary:            true,
	}})
	if err != nil {
		return addr, err
	}
	if _, err := a.c.CreateAddressKey(ctx, proton.CreateAddressKeyReq{
		AddressID:     addr.ID,
		PrivateKey:    armored,
		Primary:       true,
		SignedKeyList: skl,
		Token:         encArm,
		Signature:     sigArm,
	}); err != nil {
		return addr, fmt.Errorf("creating its key: %w", err)
	}
	return addr, nil
}
