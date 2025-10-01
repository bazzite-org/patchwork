obj-$(CONFIG_AYN) += ayn_platform/
obj-$(CONFIG_AYANEO) += ayaneo_platform/
obj-$(CONFIG_BMI260) += bmi260/

obj-$(CONFIG_XONEDO) += xonedo/
obj-$(CONFIG_XPADNEO) += xpadneo/hid-xpadneo/src/
obj-$(CONFIG_FANATEC) += fanatecff/
obj-$(CONFIG_LG4FF) += lg4ff/
obj-$(CONFIG_GCAOC) += gcadapter_oc/
obj-$(CONFIG_RAZER) += razer/driver/

obj-$(CONFIG_WL) += broadcom-wl/
obj-$(CONFIG_NCT6687D) += nct6687d/

obj-$(CONFIG_FWOOT) += framework/
obj-$(CONFIG_S76) += system76/
obj-$(CONFIG_S76IO) += system76_io/

obj-$(CONFIG_ZENERGY) += zenergy/
obj-$(CONFIG_KVFM) += kvfm/module/
# evdi incorrectly picks those variables up
CFLAGS :=
export CFLAGS
obj-$(CONFIG_DRM_EVDI) += evdi/module/
obj-$(CONFIG_V4L2LOOP) += v4l2loopback/
obj-$(CONFIG_VHBA) += cdemu/vhba-module/
obj-$(CONFIG_FACETIMEHD) += facetimehd/

# Install common files from all modules
install:
	install -D modules-load.conf $(INSTALL_DIR)/usr/lib/modules-load.d/20-akmods.conf
	install -D modprobe.conf $(INSTALL_DIR)/usr/lib/modprobe.d/20-akmods.conf

	install -D razer/install_files/udev/99-razer.rules $(INSTALL_DIR)/usr/lib/udev/rules.d/70-razer.rules
	install -D -m 0755 razer/install_files/udev/razer_mount $(INSTALL_DIR)/usr/lib/udev/razer_mount

	install -D cdemu/vhba-module/debian/vhba-dkms.udev $(INSTALL_DIR)/usr/lib/udev/rules.d/70-vhba.rules
	install -D xonedo/install/modprobe.conf $(INSTALL_DIR)/usr/lib/modprobe.d/xone.conf

	make -C v4l2loopback/utils/
	install -D -m 0755 v4l2loopback/utils/v4l2loopback-ctl $(INSTALL_DIR)/usr/bin/v4l2loopback-ctl