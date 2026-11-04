# Google: Gmail, Drive, Photos. Being left (modules/migration).
{
  accounts = {
    roles.google = [ "platform" ];

    capabilities.google = {
      takeout = "flag";
      photosLibraryApi = "flag";
      dataPortabilityApi = "flag";
    };

    plans.google.free = {
      # 15 GB free
      billing = {
        value = "free";
        source = "https://one.google.com/about/plans";
      };
      checked = "2026-11-01";
      capabilities = {
        # a full copy, requested in its own console
        takeout = {
          value = true;
          source = "https://takeout.google.com/";
        };
        # whole-library reads ended 2025-03-31
        photosLibraryApi = {
          value = false;
          source = "https://developers.google.com/photos/support/updates";
        };
        # EEA/UK users only
        dataPortabilityApi = {
          value = false;
          source = "https://developers.google.com/data-portability";
        };
      };
    };

    held.google-mirazo = {
      provider = "google";
      plan = "free";
      owner = "mirazo";
      status = "retiring";
      login = {
        item = "Google";
        email = "oshodi.zach@gmail.com";
      };
    };
  };
}
