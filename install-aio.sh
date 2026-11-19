#!/usr/bin/env bash
# =============================================================================
#  OpenStack all-in-one (Kolla-Ansible) na Ubuntu 24.04 – LAB, nie produkcja!
#  Uruchom jako zwykły użytkownik (nie root):  ./install-aio.sh
#  Log: ~/install-aio.log
# =============================================================================

# ---------- ZMIENNE DO POPRAWIENIA -------------------------------------------
MGMT_IF="ens33"                 # karta z IP (management, API, Horizon)
EXT_IF="ens37"                  # karta BEZ IP (sieć zewnętrzna Neutrona)
MGMT_IP="192.168.180.10"        # IP na MGMT_IF

# Sieć zewnętrzna = podsieć VMnet8 (NAT). Pula floating IP poza DHCP VMware.
EXT_NET_CIDR="192.168.180.0/24"
EXT_NET_GATEWAY="192.168.180.2"
EXT_NET_RANGE="start=192.168.180.100,end=192.168.180.120"  # .51-.55 zajmuje k3s!

CINDER_DISK="/dev/sdb"          # pusty dysk dla Cindera (LVM); "" = bez Cindera
KOLLA_BRANCH=""                 # "" = najnowsza gałąź stable/*, albo np. "stable/2025.2"
# -----------------------------------------------------------------------------

set -euo pipefail
exec > >(tee -a "$HOME/install-aio.log") 2>&1

VENV="$HOME/kolla-venv"
INVENTORY="$HOME/all-in-one"

step() { echo; echo "=================== $* ==================="; }
die()  { echo "BŁĄD: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "uruchom jako zwykły użytkownik, nie root"

# ---------- 1. Sprawdzenia ---------------------------------------------------
step "1/9 Sprawdzam środowisko"

. /etc/os-release
[[ "$ID" == "ubuntu" ]] || die "skrypt jest dla Ubuntu (masz: $PRETTY_NAME)"
echo "System: $PRETTY_NAME"
[[ "$VERSION_ID" == "24.04" ]] \
  || die "Kolla-Ansible wspiera Ubuntu 24.04, a masz $VERSION_ID – zainstaluj VM z ISO 24.04"

ip link show "$MGMT_IF" >/dev/null 2>&1 || die "brak karty $MGMT_IF (sprawdź: ip -br a)"
ip link show "$EXT_IF"  >/dev/null 2>&1 || die "brak karty $EXT_IF (sprawdź: ip -br a)"
ip -4 addr show "$MGMT_IF" | grep -q "inet $MGMT_IP/" \
  || die "$MGMT_IF nie ma adresu $MGMT_IP (popraw netplan albo zmienną MGMT_IP)"
if ip -4 addr show "$EXT_IF" | grep -q inet; then
  die "$EXT_IF ma adres IPv4 – musi być bez IP (popraw netplan)"
fi
sudo ip link set "$EXT_IF" up

if grep -Eq 'vmx|svm' /proc/cpuinfo; then
  VIRT_TYPE="kvm"
  echo "Nested KVM: OK -> nova_compute_virt_type=kvm"
else
  VIRT_TYPE="qemu"
  echo "UWAGA: brak VT-x/AMD-V w VM -> qemu (instancje będą wolne)."
  echo "       Włącz 'Virtualize Intel VT-x/EPT' w ustawieniach procesora VM."
fi

MEM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
DISK_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
echo "RAM: ${MEM_GB} GB, wolne na /: ${DISK_GB} GB"
(( MEM_GB >= 7 ))   || die "za mało RAM (min. 8 GB, zalecane 16 GB)"
(( DISK_GB >= 40 )) || die "za mało miejsca na / (min. 40 GB). Rozciągnij LVM – patrz README."

# ---------- 2. sudo bez hasła (lab) ------------------------------------------
step "2/9 sudo bez hasła dla $USER (wymagane przez Ansible – tylko lab!)"
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/kolla-$USER" >/dev/null
sudo chmod 440 "/etc/sudoers.d/kolla-$USER"

# ---------- 3. Pakiety -------------------------------------------------------
step "3/9 Pakiety systemowe"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git python3-dev python3-venv libffi-dev gcc libssl-dev \
  libdbus-glib-1-dev pkg-config lvm2 curl

# ---------- 4. Dysk dla Cindera ----------------------------------------------
step "4/9 Dysk dla Cindera"
ENABLE_CINDER="no"
if [[ -n "$CINDER_DISK" ]]; then
  if sudo vgs cinder-volumes >/dev/null 2>&1; then
    echo "Grupa LVM cinder-volumes już istnieje – używam jej."
    ENABLE_CINDER="yes"
  elif [[ ! -b "$CINDER_DISK" ]]; then
    echo "UWAGA: brak dysku $CINDER_DISK – instaluję bez Cindera."
  elif [[ $(lsblk -n -o NAME "$CINDER_DISK" | wc -l) -ne 1 ]] \
       || [[ -n "$(sudo blkid -p "$CINDER_DISK" 2>/dev/null || true)" ]] \
       || findmnt -S "$CINDER_DISK" >/dev/null 2>&1; then
    echo "UWAGA: $CINDER_DISK nie jest pusty (partycje/system plików) – NIE ruszam go."
    echo "       Instaluję bez Cindera."
  else
    echo "Tworzę LVM cinder-volumes na pustym dysku $CINDER_DISK"
    sudo pvcreate "$CINDER_DISK"
    sudo vgcreate cinder-volumes "$CINDER_DISK"
    ENABLE_CINDER="yes"
  fi
fi
echo "Cinder: $ENABLE_CINDER"

# ---------- 5. Kolla-Ansible -------------------------------------------------
step "5/9 Instalacja Kolla-Ansible"
if [[ -z "$KOLLA_BRANCH" ]]; then
  KOLLA_BRANCH=$(git ls-remote --heads https://opendev.org/openstack/kolla-ansible 'refs/heads/stable/20*' \
                 | awk -F'refs/heads/' '{print $2}' | sort -V | tail -1)
  [[ -n "$KOLLA_BRANCH" ]] || die "nie udało się ustalić gałęzi stable kolla-ansible"
fi
RELEASE="${KOLLA_BRANCH#stable/}"
echo "Gałąź kolla-ansible: $KOLLA_BRANCH (release $RELEASE)"
echo "UWAGA: sprawdź w https://docs.openstack.org/kolla-ansible/$RELEASE/user/support-matrix.html,"
echo "       czy ta wersja wspiera Ubuntu $VERSION_ID. Jeśli nie – ustaw KOLLA_BRANCH ręcznie."

[[ -d "$VENV" ]] || python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -U pip wheel
pip install "git+https://opendev.org/openstack/kolla-ansible@${KOLLA_BRANCH}"
command -v ansible-playbook >/dev/null || pip install "ansible-core"
# AIO: Ansible używa Pythona z venv, więc tu muszą być Docker SDK i dbus-python
pip install docker dbus-python
ansible --version | head -1

sudo mkdir -p /etc/kolla
sudo chown "$USER:$USER" /etc/kolla
if [[ ! -f /etc/kolla/passwords.yml ]]; then
  cp -r "$VENV/share/kolla-ansible/etc_examples/kolla/"* /etc/kolla/
fi
cp "$VENV/share/kolla-ansible/ansible/inventory/all-in-one" "$INVENTORY"
[[ -f /etc/kolla/globals.yml.example ]] || cp /etc/kolla/globals.yml /etc/kolla/globals.yml.example

# Ansible Galaxy bywa wolne – dłuższy timeout i kilka podejść
export ANSIBLE_GALAXY_SERVER_TIMEOUT=300
for try in 1 2 3; do
  kolla-ansible install-deps && break
  [[ $try -eq 3 ]] && die "install-deps nie powiodło się 3 razy (Ansible Galaxy) – uruchom skrypt ponownie później"
  echo "install-deps: próba $try nieudana, ponawiam za 30 s..."
  sleep 30
done
kolla-genpwd     # uzupełnia tylko puste hasła, istniejących nie zmienia

# ---------- 6. globals.yml ---------------------------------------------------
step "6/9 Konfiguracja /etc/kolla/globals.yml"
cat > /etc/kolla/globals.yml <<EOF
---
# Wygenerowane przez install-aio.sh. Pełna lista opcji: /etc/kolla/globals.yml.example
workaround_ansible_issue_8743: yes

kolla_base_distro: "ubuntu"

# Sieć
network_interface: "${MGMT_IF}"
neutron_external_interface: "${EXT_IF}"
kolla_internal_vip_address: "${MGMT_IP}"
enable_haproxy: "no"            # 1 node = brak HA, API wprost na IP hosta

# Nova
nova_compute_virt_type: "${VIRT_TYPE}"

# Cinder (wolumeny) na LVM
enable_cinder: "${ENABLE_CINDER}"
enable_cinder_backend_lvm: "${ENABLE_CINDER}"
enable_cinder_backup: "no"
cinder_volume_group: "cinder-volumes"
EOF
cat /etc/kolla/globals.yml

# ---------- 7. Wdrożenie -----------------------------------------------------
# Obrazy z quay.io/openstack.kolla to obrazy z CI projektu – Kolla 2026.x wymaga
# świadomej zgody (flaga istnieje tylko w prechecks).
# Do labu OK; na produkcji: własny rejestr albo kolla-build.
TEST_IMAGES="--use-test-images"

step "7/9 bootstrap-servers (Docker, użytkownicy, sysctl)"
kolla-ansible bootstrap-servers -i "$INVENTORY"

step "7/9 prechecks"
kolla-ansible prechecks -i "$INVENTORY" $TEST_IMAGES

step "7/9 pull (pobieranie obrazów – najdłuższy etap)"
kolla-ansible pull -i "$INVENTORY"

step "7/9 deploy"
kolla-ansible deploy -i "$INVENTORY"

step "7/9 post-deploy (admin-openrc.sh, clouds.yaml)"
kolla-ansible post-deploy -i "$INVENTORY"
sudo chown "$USER:$USER" /etc/kolla/admin-openrc.sh /etc/kolla/clouds.yaml 2>/dev/null || true

# Logi Kolla są w wolumenie Dockera kolla_logs – skrót /var/log/kolla dla wygody
if [[ ! -e /var/log/kolla ]]; then
  sudo ln -s /var/lib/docker/volumes/kolla_logs/_data /var/log/kolla
fi

# ---------- 8. Klient + dane startowe ----------------------------------------
step "8/9 Klient OpenStack + init-runonce (obraz cirros, sieci, flavory)"
CONSTRAINTS="https://releases.openstack.org/constraints/upper/${RELEASE}"
pip install python-openstackclient -c "$CONSTRAINTS" || pip install python-openstackclient

# shellcheck disable=SC1091
source /etc/kolla/admin-openrc.sh
if ! openstack network show public1 >/dev/null 2>&1; then
  EXT_NET_CIDR="$EXT_NET_CIDR" EXT_NET_RANGE="$EXT_NET_RANGE" EXT_NET_GATEWAY="$EXT_NET_GATEWAY" \
    "$VENV/share/kolla-ansible/init-runonce"
else
  echo "Sieć public1 już istnieje – pomijam init-runonce."
fi

# ---------- 9. Podsumowanie --------------------------------------------------
step "9/9 GOTOWE"
ADMIN_PASS=$(grep '^keystone_admin_password' /etc/kolla/passwords.yml | awk '{print $2}')
cat <<EOF

  Horizon:  http://${MGMT_IP}
  Login:    admin
  Hasło:    ${ADMIN_PASS}

  CLI:
    source ~/kolla-venv/bin/activate
    source /etc/kolla/admin-openrc.sh
    openstack service list

  Teraz zrób snapshot VM w VMware i przejdź do cwiczenia.md.
EOF
