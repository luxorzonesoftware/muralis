pkgname=muralis
pkgver=1.0.0
pkgrel=1
pkgdesc="Minimal wallpaper shuffler for X11 and Sway"
arch=('any')
url="https://github.com/luxorzonesoftware/muralis"
license=('GPL2')
depends=('bash' 'coreutils' 'findutils')
optdepends=('feh: wallpaper setting on X11'
            'xorg-xrandr: monitor detection on X11'
            'xorg-xev: watch mode on X11'
            'sway: Wayland compositor support'
            'jq: JSON parsing for sway backend'
            'dialog: terminal GUI'
            'whiptail: terminal GUI'
            'fzf: fuzzy finder GUI')
source=("https://github.com/luxorzonesoftware/muralis/archive/refs/tags/v${pkgver}.tar.gz")
sha256sums=('SKIP')

package() {
  cd "${srcdir}/muralis-${pkgver}"
  install -Dm755 muralis.sh "${pkgdir}/usr/bin/muralis"
  install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
  install -Dm644 README.md "${pkgdir}/usr/share/doc/${pkgname}/README.md"
}
