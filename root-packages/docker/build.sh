TERMUX_PKG_HOMEPAGE=https://docker.com
TERMUX_PKG_DESCRIPTION="Set of products that use OS-level virtualization to deliver software in packages called containers."
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=23.0.1
DOCKER_GITCOMMIT=a5ee5b1
TERMUX_PKG_SRCURL=(https://github.com/moby/moby/archive/v${TERMUX_PKG_VERSION}.tar.gz
                   https://github.com/docker/cli/archive/v${TERMUX_PKG_VERSION}.tar.gz)
TERMUX_PKG_SHA256=(c8e6c0ac5f0c772023e3430f80190e0f86644b6d94cac63118b03561385f7b56
                   37bc1c71a782fc10d35aa6708c1b3c90a71f3947c33665cb0de68df25dc14d94)
TERMUX_PKG_DEPENDS="containerd, libdevmapper"
TERMUX_PKG_CONFFILES="etc/docker/daemon.json"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_SKIP_SRC_EXTRACT=true

termux_step_get_source() {
	local PKG_SRCURL=(${TERMUX_PKG_SRCURL[@]})
	local PKG_SHA256=(${TERMUX_PKG_SHA256[@]})

	if [ ${#PKG_SRCURL[@]} != ${#PKG_SHA256[@]} ]; then
		termux_error_exit "Error: length of TERMUX_PKG_SRCURL isn't equal to length of TERMUX_PKG_SHA256."
	fi

	# download and extract packages into its own folder inside $TERMUX_PKG_SRCDIR
	mkdir -p "$TERMUX_PKG_CACHEDIR"
	mkdir -p "$TERMUX_PKG_SRCDIR"
	for i in $(seq 0 $(( ${#PKG_SRCURL[@]} - 1 ))); do
		local file="${TERMUX_PKG_CACHEDIR}/$(basename ${PKG_SRCURL[$i]})"
		rm -rf "$file"
		termux_download "${PKG_SRCURL[$i]}" "$file" "${PKG_SHA256[$i]}"
		tar xf "$file" -C "$TERMUX_PKG_SRCDIR"
	done

	# delete trailing -$TERMUX_PKG_VERSION from folder name
	# so patches become portable across different versions
	cd "$TERMUX_PKG_SRCDIR"
	for folder in $(ls); do
		if [ ! $folder == ${folder%%-*} ]; then
			mv $folder ${folder%%-*}
		fi
	done
}

termux_step_make() {
	# setup go build environment
	termux_setup_golang
	export GO111MODULE=auto

	# BUILD DOCKERD DAEMON
	echo -n "Building dockerd daemon..."
	(
	set -e
	cd moby

	# apply some patches in a batch
	xargs sed -i "s_\(/etc/docker\)_${TERMUX_PREFIX}\1_g" < <(grep -R /etc/docker | cut -d':' -f1 | sort | uniq)
	xargs sed -i 's_\(/run/docker/plugins\)_/data/docker\1_g' < <(grep -R '/run/docker/plugins' | cut -d':' -f1 | sort | uniq)
	xargs sed -i 's/[a-zA-Z0-9]*\.GOOS/"linux"/g' < <(grep -R '[a-zA-Z0-9]*\.GOOS' | cut -d':' -f1 | sort | uniq)

	# issue the build command
	export DOCKER_GITCOMMIT
	export DOCKER_BUILDTAGS='exclude_graphdriver_btrfs exclude_graphdriver_devicemapper exclude_graphdriver_quota selinux exclude_graphdriver_aufs'
	# horrible, but effective way to apply patches on the fly while compiling
	while ! IFS='' files=$(AUTO_GOPATH=1 PREFIX='' hack/make.sh dynbinary 2>&1 1>/dev/null); do
		if ! xargs sed -i 's/\("runtime"\)/_ \1/' < <(echo $files | grep runtime | cut -d':' -f1 | cut -c38-); then
			echo $files;
			exit 1
		fi
	done
	)
	echo " Done!"

	# BUILD DOCKER-PROXY BINARY FROM LIBNETWORK
	echo -n "Building docker-proxy from libnetwork..."
	(
	set -e

	# fix path locations to build with go
	mkdir -p go/src/github.com/docker
	mv -T moby go/src/github.com/docker/docker
	mkdir moby
	mv go moby
	export GOPATH="${PWD}/moby/go"
	cd "${GOPATH}/src/github.com/docker/docker"

	# issue the build command
	go build -o docker-proxy github.com/docker/docker/cmd/docker-proxy
	)
	echo " Done!"

	# BUILD DOCKER-CLI CLIENT
	echo -n "Building docker-cli client..."
	(
	set -e

	# fix path locations to build with go
	mkdir -p go/src/github.com/docker
	mv cli go/src/github.com/docker
	mkdir cli
	mv go cli
	export GOPATH="${PWD}/cli/go"
	cd "${GOPATH}/src/github.com/docker/cli"

	# apply some patches in a batch
	xargs sed -i 's_/var/\(run/docker\.sock\)_/data/docker/\1_g' < <(grep -R /var/run/docker\.sock | cut -d':' -f1 | sort | uniq)

	# issue the build command
	export VERSION=v${TERMUX_PKG_VERSION}-ce
	export DISABLE_WARN_OUTSIDE_CONTAINER=1
	export LDFLAGS="-L ${TERMUX_PREFIX}/lib -r ${TERMUX_PREFIX}/lib"
	make -j ${TERMUX_MAKE_PROCESSES} dynbinary
	unset GOOS GOARCH CGO_LDFLAGS CC CXX CFLAGS CXXFLAGS LDFLAGS
	make -j ${TERMUX_MAKE_PROCESSES} manpages
	)
	echo " Done!"
}

termux_step_make_install() {
	install -Dm 700 moby/go/src/github.com/docker/docker/bundles/dynbinary-daemon/dockerd ${TERMUX_PREFIX}/libexec/dockerd
	install -Dm 700 moby/go/src/github.com/docker/docker/docker-proxy ${TERMUX_PREFIX}/bin/docker-proxy
	install -Dm 700 cli/go/src/github.com/docker/cli/build/docker-android-* ${TERMUX_PREFIX}/bin/docker
	install -Dm 600 -t ${TERMUX_PREFIX}/share/man/man1 cli/go/src/github.com/docker/cli/man/man1/*
	install -Dm 600 -t ${TERMUX_PREFIX}/share/man/man5 cli/go/src/github.com/docker/cli/man/man5/*
	install -Dm 600 -t ${TERMUX_PREFIX}/share/man/man8 cli/go/src/github.com/docker/cli/man/man8/*
	install -Dm 600 ${TERMUX_PKG_BUILDER_DIR}/daemon.json ${TERMUX_PREFIX}/etc/docker/daemon.json
	sed -e "s|@TERMUX_PREFIX@|$TERMUX_PREFIX|g" \
	       "${TERMUX_PKG_BUILDER_DIR}/dockerd.sh" > "${TERMUX_PREFIX}/bin/dockerd"
	chmod 700 "${TERMUX_PREFIX}/bin/dockerd"
}

termux_step_create_debscripts() {
	cat <<- EOF > postinst
		#!${TERMUX_PREFIX}/bin/sh

		echo 'NOTE: Docker requires the kernel to support'
		echo 'device cgroups, namespace, VETH, among others.'
		echo
		echo 'To check a full list of features needed, run the script:'
		echo 'https://github.com/moby/moby/blob/master/contrib/check-config.sh'
	EOF
}
