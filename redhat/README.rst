Bazzite Kernel
==============

This repository contains the Bazzite kernel, built directly
from the Fedora Always Ready Kernel
(`kernel-ark <https://gitlab.com/cki-project/kernel-ark>`__) repository.

The repository itself or the build process have had no changes, with the
one addition being the large set of handheld and performance
optimization patches Bazzite users have come to expect. These include
the latest in handheld compatibility patches (OneXPlayer, ROG Ally,
Steam Deck LCD/OLED, Surface devices) and stability fixes.

Those patches are applied directly on top of the Fedora patchset
`here <./patch-handheld.patch>`__, after being rebased on top of the ARK
kernel tree in the patchwork
`repo <https://github.com/hhd-dev/patchwork>`__.

To make it Github friendly, this repository contains actions and
containers to build the kernel and generate the RPMs in Github. As a
bonus point, each release includes a repackaged version of the kernel
for Arch.

Installing
----------

Fedora is TODO. Of course, you can always install Bazzite :).

For Arch, the kernel is available in the AUR.

.. code:: bash

   # Use your favorite AUR helper (e.g., paru, pikaur, yay)
   yay -S linux-bazzite-bin

Contributing
------------

If you find that a patch is missing, or you have a patch that you think
should be included, please open an issue with a link to the patch or
the lore.

DO NOT OPEN A PULL REQUEST. The `handheld.patch` file is generated
automatically from the patchwork repository, and any changes to it
will be overwritten.