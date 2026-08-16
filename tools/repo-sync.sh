#!/bin/sh
# repo-sync.sh — mirror hand-edited SOURCE from the live build tree into this
# (source-only) repo, ready to commit + push. Prebuilt binaries and build
# outputs are excluded here AND by .gitignore; regenerate them per the README.
# Uses rsync WITHOUT --delete, so it never removes files already in the repo.
# Add more source areas below as they start changing.
set -eu
WORK=/group/bcapps/ajayad/master_thesis_rebirth/work
REPO=/group/bcapps/ajayad/master_thesis_rebirth/Wifi-HAR-Versal-VCK190-PL

# Prebuilt binaries / build artifacts never belong in the source repo.
EXC="--exclude=host --exclude=host_3br --exclude=host_diag --exclude=host_fix \
--exclude=*.xclbin --exclude=*.pdi --exclude=*.xsa --exclude=*.xo --exclude=*.o \
--exclude=*.cpio.gz* --exclude=*.BIN --exclude=Image --exclude=__pycache__"

# PetaLinux meta-user layer: recipes (.bb), systemd unit, autorun script, text vectors.
rsync -a $EXC "$WORK/petalinux/petalinux/project-spec/meta-user/" \
             "$REPO/petalinux/project-spec/meta-user/"

echo "repo-sync: PetaLinux meta-user mirrored (source only)."
