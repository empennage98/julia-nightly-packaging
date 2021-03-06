#!/bin/bash
set -e

# This script invoked by a cron job every X hours
# This script functions best when the following are installed:
#   wget, git, bzr, dch, make, python (with the "requests" module installed, for Travis-ci API)


# Note that in order to push to lp:~staticfloat/julianightlies/trunk, you need my GPG private key
TEAM=~staticfloat
PROJECT=julianightlies
JULIA_GIT_URL="https://github.com/JuliaLang/julia.git"
DEBIAN_GIT_URL="https://github.com/staticfloat/julia-debian.git"
JULIA_GIT_BRANCH=master
DEBIAN_GIT_BRANCH=master
BZR_BRANCH=trunk
BUILD_DIR=$(echo ~)/tmp/julia-packaging/ubuntu

cd $(dirname $0)
ORIG_DIR=$(pwd)

# Check if we've been downloaded as a git directory.  If so, update ourselves!
if [[ -d .git ]]; then
	git pull
fi

# Store everything in a temp dir
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# Get the git branch
if test ! -d julia-${JULIA_GIT_BRANCH}; then
	git clone ${JULIA_GIT_URL} julia-${JULIA_GIT_BRANCH}
fi

# Get the bzr branch
if test ! -d ${BZR_BRANCH}; then
	bzr branch http://bazaar.launchpad.net/${TEAM}/${PROJECT}/${BZR_BRANCH}/
fi

# Get the debian directory
if test ! -d debian-${DEBIAN_GIT_BRANCH}; then
	git clone ${DEBIAN_GIT_URL} debian-${DEBIAN_GIT_BRANCH}
else
	cd debian-${DEBIAN_GIT_BRANCH}
	git pull
	cd ..
fi

# Go into our checkout of JULIA_GIT_URL
cd julia-${JULIA_GIT_BRANCH}
git checkout ${JULIA_GIT_BRANCH}
git fetch
git reset --hard origin/${JULIA_GIT_BRANCH}

# Find the last commit that passed a Travis build
if [[ -z "$GIVEN_COMMIT" ]]; then
    LAST_GOOD_COMMIT=$(${ORIG_DIR}/get_last_good_commit.py)
    if [ -z "$LAST_GOOD_COMMIT" ]; then
        echo "ERROR: No good commits detected, going with HEAD!"
        LAST_GOOD_COMMIT="HEAD"
    fi
else
    LAST_GOOD_COMMIT="$GIVEN_COMMIT"
fi

git checkout -B ${JULIA_GIT_BRANCH} ${LAST_GOOD_COMMIT}
if [[ "$?" != "0" ]]; then
	echo "Couldn't detect best last commit, going with HEAD!"
	git checkout HEAD
fi

git submodule init
git submodule update

# Hack to get around our lack of packaging of Rmath
make -C deps get-dsfmt

# same for utf8proc
make -C deps get-utf8proc

# We're going to compile LLVM as well!
make -C deps get-llvm

# Work around our lack of git on buildd servers
make -C base version_git.jl.phony

# Make it blaringly obvious to everyone that this is a git build when they start up Julia-
JULIA_VERSION=$(cat ./VERSION)
DATECOMMIT=$(git log --pretty=format:'%cd' --date=short -n 1 | tr -d '-')
echo "Syncing commit ${JULIA_VERSION}+$DATECOMMIT."
cd ..

# Now go into the bzr branch and copy everything over
cd ${BZR_BRANCH}
bzr pull http://bazaar.launchpad.net/${TEAM}/${PROJECT}/${BZR_BRANCH}/
rm -rf *
cp -r ../julia-${JULIA_GIT_BRANCH}/* .

# Throw the debian directory into here as well, instead of relying on launchpad
cp -r ../debian-${DEBIAN_GIT_BRANCH}/debian .

# Also, increment the current debian changelog, so we get git version tagged binaries
dch -v "${JULIA_VERSION}+$DATECOMMIT" "nightly git build"

bzr add
bzr ci -m "Manual import commit ${DATECOMMIT} from ${JULIA_GIT_URL}/${JULIA_GIT_BRANCH}" || true
bzr push lp:${TEAM}/${PROJECT}/${BZR_BRANCH}
cd ..

# Report to status.julialang.org
#${ORIG_DIR}/report_nightly.jl "Ubuntu" $JULIA_COMMIT "https://launchpad.net/~staticfloat/+archive/julianightlies"

exit 0
