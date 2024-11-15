# Bazzite Kernel patchwork

Welcome to the Bazzite kernel patchwork repository. Here, you can find the patch series that is currently used on Bazzite, in addition to a tagged history of all the previous series.

When parts of the Bazzite patch series are ready for upstreaming, you might see an additional temporary branch for them, starting with `upstream/`.

## Generating srpm
To generate an srpm from this repository, use one of the bazzite-* branches, then run:
```bash
dist=.fc42
relver=1
make -C redhat dist-srpm -j $(expr $(nproc) - 2) \
        DIST=$dist DISTLOCALVERSION=.bazzite BUILD=$relver
```

## Contributing

If you believe a patch is missing or a patch should be included, please open an issue with the patch or lore link in the [kernel-bazzite](https://github.com/hhd-dev/kernel-bazzite) repository.

> [!WARNING]
> Do not open Pull Requests or issues in this repository!! They will be closed.