# The Cloudflare state, rebuilt (2026-11-01): a failed save deleted the only
# copy (secretspec deleted the old item before its create was refused; the
# patch now creates first). Every object below was live and unchanged; the
# ids were read from Cloudflare's API by matching zone, name, type and
# content to the declared records, exactly one each. After the next apply
# the state holds them and these imports are no-ops.
{
  cloudflare.imports = {
    "cloudflare_dns_record.jingzo-org-proton-dkim" =
      "6e79f3b9333039e6e843b08a75475174/f3774163c21541d2058e8e47500ed43b";
    "cloudflare_dns_record.jingzo-org-proton-dkim2" =
      "6e79f3b9333039e6e843b08a75475174/b53d495110fb69542ddeee74010acb54";
    "cloudflare_dns_record.jingzo-org-proton-dkim3" =
      "6e79f3b9333039e6e843b08a75475174/c6a1c44d0b8832ff3e93b912d8523784";
    "cloudflare_dns_record.jingzo-org-proton-dmarc" =
      "6e79f3b9333039e6e843b08a75475174/859fd30fa835783e84432f19132c0f37";
    "cloudflare_dns_record.jingzo-org-proton-mx-1" =
      "6e79f3b9333039e6e843b08a75475174/3857d2ad26f68b7f306f3cc790fe58c3";
    "cloudflare_dns_record.jingzo-org-proton-mx-2" =
      "6e79f3b9333039e6e843b08a75475174/f8f63fbe5fdf62a58bd45d39a6f6b39b";
    "cloudflare_dns_record.jingzo-org-proton-spf" =
      "6e79f3b9333039e6e843b08a75475174/03608ed28d1afff9290f32566aedf538";
    "cloudflare_dns_record.jingzo-org-proton-verification" =
      "6e79f3b9333039e6e843b08a75475174/9b779f5dbf8e21dbba1a4539e9439fe0";
    "cloudflare_dns_record.kagamizo-com-github-verification" =
      "2f1f4505269c5d5ea904ca73d379ef99/9f8b5897e88f678ba4e29c57f1c33d7d";
    "cloudflare_dns_record.kagamizo-com-proton-dkim" =
      "2f1f4505269c5d5ea904ca73d379ef99/0482b5f007edbe5587c89e5296ac890b";
    "cloudflare_dns_record.kagamizo-com-proton-dkim2" =
      "2f1f4505269c5d5ea904ca73d379ef99/8bd4e47066130319dea799d2801cbc72";
    "cloudflare_dns_record.kagamizo-com-proton-dkim3" =
      "2f1f4505269c5d5ea904ca73d379ef99/ef86084bb1839457df1685f258e53941";
    "cloudflare_dns_record.kagamizo-com-proton-dmarc" =
      "2f1f4505269c5d5ea904ca73d379ef99/7c040bc966e899bc7d2ae802a3e98ab9";
    "cloudflare_dns_record.kagamizo-com-proton-mx-1" =
      "2f1f4505269c5d5ea904ca73d379ef99/e4ce12c1deb9ce0cf39a00f7841ed2c8";
    "cloudflare_dns_record.kagamizo-com-proton-mx-2" =
      "2f1f4505269c5d5ea904ca73d379ef99/34ec479805e07c82347a89c9f6a2eb81";
    "cloudflare_dns_record.kagamizo-com-proton-spf" =
      "2f1f4505269c5d5ea904ca73d379ef99/a99665e6ce4f688c8c00ea0beef3fc81";
    "cloudflare_dns_record.kagamizo-com-proton-verification" =
      "2f1f4505269c5d5ea904ca73d379ef99/4ebf86de08cf4dc8926de322651e390c";
    "cloudflare_dns_record.mirazo-org-proton-dkim" =
      "cb57e0ebb1989ae3d67be0b64cc923ae/c7ffb11b99e7ee9c69f0761ebeb4916d";
    "cloudflare_dns_record.mirazo-org-proton-dkim2" =
      "cb57e0ebb1989ae3d67be0b64cc923ae/5afc21cbbfb4218d9b69d36bb00da756";
    "cloudflare_dns_record.mirazo-org-proton-dkim3" =
      "cb57e0ebb1989ae3d67be0b64cc923ae/82d9fea321cb875dc022bbe493338b97";
    "cloudflare_dns_record.mirazo-org-proton-dmarc" =
      "cb57e0ebb1989ae3d67be0b64cc923ae/95a158285a32f26bd4b95dce95b68dab";
    "cloudflare_dns_record.mirazo-org-proton-mx-1" =
      "cb57e0ebb1989ae3d67be0b64cc923ae/da9611d4050602284b9aa0e4f77f3506";
    "cloudflare_dns_record.mirazo-org-proton-mx-2" =
      "cb57e0ebb1989ae3d67be0b64cc923ae/c6765908efaf257a6876627a33e74971";
    "cloudflare_dns_record.mirazo-org-proton-spf" =
      "cb57e0ebb1989ae3d67be0b64cc923ae/03d756340775a392dda133d93519b6d2";
    "cloudflare_dns_record.mirazo-org-proton-verification" =
      "cb57e0ebb1989ae3d67be0b64cc923ae/71e34eb919e90815124cd891ba2d7b81";
    "cloudflare_workers_script.status" = "73f11fa58ac09529a4fb40284b8ce236/kagamizo-status";
    # Made by the owner's Zero Trust onboarding (2026-11-03), adopted here.
    "cloudflare_zero_trust_organization.kagamizo" = "73f11fa58ac09529a4fb40284b8ce236";
  };
}
