_: {
  /*
    NVIDIA-specific client variables shared by NVIDIA graphical hosts.
    Driver selection and hardware workarounds remain host-owned.
  */
  environment.sessionVariables = {
    # Select NVIDIA's libglvnd vendor for XWayland clients.
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    # Select NVIDIA's VA-API translation driver for hardware video.
    LIBVA_DRIVER_NAME = "nvidia";
  };
}
