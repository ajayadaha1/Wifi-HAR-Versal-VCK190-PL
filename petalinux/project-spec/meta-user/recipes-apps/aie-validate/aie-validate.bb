SUMMARY = "AIE DDR->AIE->DDR validation: 3-branch host + xclbin + vectors + boot auto-run"
DESCRIPTION = "Prebuilt aarch64 XRT host app (host_3br), feature_graph_3br.xclbin and \
input/golden vectors for the 3 branches (motion, breathing, phase) at \
/home/root/aie-validate, plus a systemd service that runs the 3-branch \
DDR->AIE->DDR check at boot and prints PASS/FAIL to the console (com0)."
LICENSE = "CLOSED"

SRC_URI = "file://host \
           file://host_3br \
           file://feature_graph.xclbin \
           file://feature_graph_3br.xclbin \
           file://input.txt \
           file://golden.txt \
           file://breath_input.txt \
           file://breath_golden.txt \
           file://phase_input.txt \
           file://phase_golden.txt \
           file://run_on_target.sh \
           file://aie-validate-autorun.sh \
           file://aie-validate.service"

S = "${WORKDIR}"

# Installs prebuilt artifacts only; do NOT pull the cross toolchain — the shared
# sstate gcc-cross is broken (ranlib hardlink error in do_prepare_recipe_sysroot).
INHIBIT_DEFAULT_DEPS = "1"
INSANE_SKIP:${PN} += "arch already-stripped ldflags file-rdeps"
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
# Prebuilt aarch64 ELFs: skip debug-split (needs the cross objcopy we intentionally don't pull).
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"

FILES:${PN} += "/home/root/aie-validate /etc/systemd/system"

do_install() {
    install -d ${D}/home/root/aie-validate
    install -m 0755 ${S}/host ${D}/home/root/aie-validate/host
    install -m 0755 ${S}/host_3br ${D}/home/root/aie-validate/host_3br
    install -m 0755 ${S}/run_on_target.sh ${D}/home/root/aie-validate/run_on_target.sh
    install -m 0755 ${S}/aie-validate-autorun.sh ${D}/home/root/aie-validate/aie-validate-autorun.sh
    install -m 0644 ${S}/feature_graph.xclbin ${D}/home/root/aie-validate/feature_graph.xclbin
    install -m 0644 ${S}/feature_graph_3br.xclbin ${D}/home/root/aie-validate/feature_graph_3br.xclbin
    install -m 0644 ${S}/input.txt ${D}/home/root/aie-validate/input.txt
    install -m 0644 ${S}/golden.txt ${D}/home/root/aie-validate/golden.txt
    install -m 0644 ${S}/breath_input.txt ${D}/home/root/aie-validate/breath_input.txt
    install -m 0644 ${S}/breath_golden.txt ${D}/home/root/aie-validate/breath_golden.txt
    install -m 0644 ${S}/phase_input.txt ${D}/home/root/aie-validate/phase_input.txt
    install -m 0644 ${S}/phase_golden.txt ${D}/home/root/aie-validate/phase_golden.txt

    # systemd unit + manual enable symlink (avoids needing systemctl-native)
    install -d ${D}/etc/systemd/system/multi-user.target.wants
    install -m 0644 ${S}/aie-validate.service ${D}/etc/systemd/system/aie-validate.service
    ln -sf ../aie-validate.service ${D}/etc/systemd/system/multi-user.target.wants/aie-validate.service
}
