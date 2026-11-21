# Plan nauki: 5 dni × (4 h OpenStack + 2 h Linux)

Linux ćwiczymy na tej samej VM (`openstack-aio`), dobierając temat do OpenStacka z danego dnia –
OpenStack to w praktyce Linux: KVM, Open vSwitch, LVM, systemd, namespace'y, iptables.

Na każdy temat: **zrób → wyjaśnij na głos jednym zdaniem → zanotuj w `dziennik.md`.**

> Przed startem: snapshot VM („openstack dziala”). Psuć wolno – od tego jest snapshot.

---

## Dzień 1 – Architektura + pierwsza instancja | Linux: system, procesy, usługi

**OpenStack (4 h)** – `cwiczenia.md` ćw. 1–2: usługi, droga „uruchom instancję”, VM cirros + floating IP.

**Linux (2 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| Informacje o systemie | `uname -a`, `cat /etc/os-release`, `hostnamectl`, `uptime` | jaka wersja jądra i systemu? |
| Procesy | `ps aux`, `ps -ef --forest`, `top`/`htop`, `pgrep -af`, `kill`, `nice` | znajdź proces `qemu` Twojej instancji cirros – ile RAM zajmuje? |
| systemd | `systemctl status/start/stop/restart/enable`, `systemctl list-units --failed` | status `docker`, `ssh`; które usługi startują z systemem? |
| Logi | `journalctl -u docker -n 50`, `journalctl -f`, `journalctl --since "10 min ago"`, `dmesg -T` | co Docker logował przy restarcie? |
| Pamięć i CPU | `free -h`, `nproc`, `lscpu`, `vmstat 1 5`, `cat /proc/meminfo` | ile RAM zjadł OpenStack? |

**Pytanie kontrolne:** czym różni się `systemctl restart` od `reload`? Co to PID 1?

---

## Dzień 2 – Sieci Neutron | Linux: sieci (najważniejszy dzień)

**OpenStack (4 h)** – ćw. 4: własna sieć, router, security group; `ip netns`, `ovs-vsctl show`, floating IP = NAT.

**Linux (2 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| Interfejsy i adresy | `ip a`, `ip -br a`, `ip link set ... up/down` | czemu `ens37` jest UP bez IP? |
| Routing | `ip route`, `ip route get 1.1.1.1` | którędy VM wychodzi do internetu? |
| DNS | `resolvectl status`, `dig`, `cat /etc/resolv.conf` | skąd VM bierze DNS? |
| Porty i połączenia | `ss -tulpn`, `ss -tnp` | które kontenery słuchają na 5000, 8774, 9696? |
| Namespace'y | `ip netns list`, `ip netns exec <ns> ip a` | wejdź do `qrouter-...` i zrób ping do instancji |
| Podgląd ruchu | `tcpdump -i <if> icmp`, `tcpdump -nn port 22` | złap ping do floating IP – na którym interfejsie go widać? |
| Firewall | `iptables -t nat -L -n -v`, `nft list ruleset` | znajdź regułę NAT floating IP w namespace routera |
| Netplan | `/etc/netplan/*.yaml`, `netplan try` | czym `try` różni się od `apply`? |

**Pytanie kontrolne:** jak sprawdzisz, czy problem jest w DNS, routingu czy firewallu? (kolejność diagnozy)

---

## Dzień 3 – Storage i tożsamość | Linux: dyski, LVM, systemy plików, uprawnienia

**OpenStack (4 h)** – ćw. 5 (Cinder), 6 (Glance + cloud-init), 3 (Keystone, kwoty).

**Linux (2 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| Dyski | `lsblk`, `blkid`, `fdisk -l`, `df -h`, `du -sh /var/lib/docker/*` | co zajmuje najwięcej miejsca? |
| LVM | `pvs`, `vgs`, `lvs`, `lvextend -r` | wolumen Cindera jako LV w `cinder-volumes` |
| iSCSI | `iscsiadm -m session`, `targetcli ls` (w kontenerze) | jak wolumen trafia do instancji? |
| Systemy plików | `mkfs.ext4`, `mount`, `/etc/fstab`, `findmnt` | sformatuj i zamontuj wolumen **w instancji** |
| Uprawnienia | `chmod`, `chown`, `umask`, `ls -l`, `stat` | czemu `passwords.yml` ma ograniczone prawa? |
| Użytkownicy i sudo | `id`, `groups`, `useradd`, `/etc/sudoers.d/`, `visudo` | co dodał skrypt w `/etc/sudoers.d/`? |

**Pytanie kontrolne:** dysk pełny – jak znajdziesz winowajcę? Co to inode i kiedy się kończą?

---

## Dzień 4 – Operacje i troubleshooting | Linux: diagnoza, wydajność, kontenery

**OpenStack (4 h)** – ćw. 7–9: resize, migracja, psucie i naprawa, `kolla-ansible reconfigure`.

**Linux (2 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| Szukanie w logach | `grep -ri error`, `less +F`, `tail -f`, `awk`, `sort \| uniq -c` | 5 najczęstszych błędów w logach Novy |
| Wydajność | `top`, `iostat -x 1`, `iotop`, `sar`, load average | co się dzieje przy uruchamianiu 3 instancji naraz? |
| Docker | `docker ps`, `logs`, `inspect`, `exec -it`, `stats` | wejdź do kontenera `nova_compute`, gdzie jest jego config? |
| KVM / libvirt | `virsh list --all`, `virsh dumpxml`, `lsmod \| grep kvm` | znajdź swoją instancję w libvirt |
| Pliki otwarte / porty | `lsof -i :5000`, `fuser` | który proces trzyma port? |
| Sygnały | `kill -15` vs `kill -9`, `trap` | czemu `-9` to ostateczność? |

**Pytanie kontrolne:** serwer „zwolnił” – jakie 5 poleceń uruchomisz najpierw i dlaczego?

---

## Dzień 5 – FortiGate + produkcja + rozmowa | Linux: bash, SSH, bezpieczeństwo

**OpenStack (4 h)** – FortiGate-VM 7.4 przed siecią zewnętrzną (2 h), teoria HA/multinode/Ceph (1 h), próbna rozmowa (1 h).

**Linux (2 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| Bash | zmienne, `if`, `for`, `$?`, `set -euo pipefail`, funkcje | przeczytaj `install-aio.sh` i wyjaśnij każdą sekcję |
| Własny skrypt | – | skrypt „health check”: usługi OpenStack, `docker ps` unhealthy, wolne miejsce |
| SSH | klucze `ssh-keygen`, `authorized_keys`, `~/.ssh/config`, `scp`, tunel `-L` | logowanie kluczem zamiast hasła |
| cron / timery | `crontab -e`, `systemctl list-timers` | uruchamiaj health check co 5 min |
| Bezpieczeństwo | `sshd_config` (PasswordAuthentication), `ufw`, aktualizacje `apt` | co byś utwardził przed produkcją? |
| Pakiety | `apt update/upgrade`, `apt show`, `dpkg -L` | skąd pochodzi pakiet `docker-ce`? |

**Pytanie kontrolne:** co robi `set -euo pipefail` i czemu jest w każdym porządnym skrypcie?

---

## Pytania z Linuksa na rozmowę

1. Co się dzieje od włączenia serwera do ekranu logowania? (BIOS/UEFI → GRUB → jądro → systemd)
2. Różnica: proces vs wątek, zombie vs sierota.
3. Jak sprawdzisz, kto słucha na porcie 443?
4. Hard link vs soft link.
5. Co to load average i czy 4.0 to dużo?
6. Dysk pokazuje 100%, ale `du` mówi mniej – dlaczego? (usunięte, ale otwarte pliki – `lsof +L1`)
7. Jak dodać miejsce na `/` bez restartu? (LVM `lvextend -r`)
8. Co to network namespace i gdzie go używa OpenStack / Docker / Kubernetes?
9. `chmod 755` vs `644` – co znaczą liczby?
10. Jak bezpiecznie zmienić konfigurację sieci na zdalnym serwerze? (`netplan try`, konsola awaryjna)
