TERMUX_PKG_HOMEPAGE=https://plantuml.com/
TERMUX_PKG_DESCRIPTION="Draws UML diagrams, using a simple and human readable text description"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.2023.1
TERMUX_PKG_SRCURL=https://downloads.sourceforge.net/project/plantuml/${TERMUX_PKG_VERSION}/plantuml-${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=33d419f8f0b0a244b41cfac3896cf084603d121d7c5b36e557d8655e9bd759ae
TERMUX_PKG_DEPENDS="openjdk-17"
TERMUX_PKG_BUILD_DEPENDS="ant"
TERMUX_PKG_PLATFORM_INDEPENDENT=true
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_make() {
	sh $TERMUX_PREFIX/bin/ant dist
}

termux_step_make_install() {
	mkdir -p $TERMUX_PREFIX/share/java
	install -Dm600 plantuml.jar $TERMUX_PREFIX/share/java/
	install -Dm700 plantuml $TERMUX_PREFIX/bin/
}
