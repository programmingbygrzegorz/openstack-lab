# Plan nauki: 5 dni × (4 h Linux + 2 h OpenStack)

**Linux to główny cel** (wymaganie „dobra znajomość Linuksa”), OpenStack jest wyróżnikiem („mile widziane”).
Wszystko ćwiczymy na tej samej VM `openstack-aio` – działający OpenStack daje prawdziwe procesy,
sieci, dyski i logi do analizy, zamiast suchych przykładów.

Na każdy temat: **zrób → wyjaśnij na głos jednym zdaniem → zanotuj w `dziennik.md`.**

> Przed startem: snapshot VM („openstack dziala”). Psuć wolno – od tego jest snapshot.

| Dzień | Linux (4 h) | OpenStack (2 h) |
|---|---|---|
| 1 | System, pliki, tekst, procesy, systemd, logi | architektura + pierwsza instancja z floating IP |
| 2 | **Sieci** (ip, routing, DNS, ss, tcpdump, firewall, namespace'y) | sieci Neutron: router, security group, OVS |
| 3 | **Dyski**, LVM, systemy plików, użytkownicy, uprawnienia | Cinder (wolumeny), Glance + cloud-init |
| 4 | **Diagnoza i wydajność**, Docker, KVM, start systemu | psucie i naprawa, `kolla-ansible reconfigure` |
| 5 | **Bash**, SSH, cron, bezpieczeństwo, pakiety | teoria produkcji (HA, Ceph) + próbna rozmowa |

Opcjonalnie po 5 dniach: FortiGate-VM 7.4 przed siecią zewnętrzną OpenStacka.

---

## Dzień 1 – Podstawy systemu

**Linux (4 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| System | `uname -a`, `cat /etc/os-release`, `hostnamectl`, `uptime` | wersja jądra i systemu |
| Struktura katalogów | `/etc`, `/var`, `/var/log`, `/proc`, `/sys`, `/home`, `/opt`, `/tmp` | gdzie leżą konfiguracja Kolli, logi, dane Dockera? |
| Nawigacja i pliki | `ls -la`, `cd`, `cp -a`, `mv`, `rm -r`, `mkdir -p`, `ln -s`, `file`, `stat` | dowiązanie `/var/log/kolla` – dokąd prowadzi? |
| Szukanie | `find / -name "*.conf" -mtime -1`, `locate`, `which`, `type` | znajdź wszystkie pliki `nova.conf` |
| Tekst | `cat`, `less`, `head`, `tail -f`, `grep -rin`, `wc`, `sort`, `uniq -c`, `cut`, `tr` | ile linii z `ERROR` w logach Neutrona? |
| sed i awk | `sed -n '10,20p'`, `sed 's/a/b/'`, `awk '{print $1}'`, `awk -F:` | wypisz loginy i powłoki z `/etc/passwd` |
| Przekierowania | `>`, `>>`, `2>`, `2>&1`, `\|`, `tee`, `xargs` | zapisz `docker ps` do pliku i policz kontenery |
| Archiwa | `tar czf`, `tar xzf`, `tar tf`, `gzip`, `zip` | spakuj `/etc/kolla` (bez `passwords.yml`!) |
| Procesy | `ps aux`, `ps -ef --forest`, `top`/`htop`, `pgrep -af`, `kill`, `nice`, `jobs`, `bg`, `fg`, `nohup` | znajdź proces `qemu` instancji – ile RAM zajmuje? |
| systemd | `systemctl status/start/stop/restart/reload/enable`, `list-units --failed`, `cat <unit>` | status `docker`, `ssh`; co startuje z systemem? |
| Logi | `journalctl -u docker -n 50`, `-f`, `--since "10 min ago"`, `-p err`, `dmesg -T` | co Docker logował przy restarcie? |

**Pytania kontrolne:** `restart` vs `reload`? Co to PID 1? Różnica `>` i `>>`? Co robi `2>&1`?

**OpenStack (2 h)** – `cwiczenia.md` ćw. 1–2: usługi, droga „uruchom instancję”, VM cirros + floating IP, SSH z Windowsa.

---

## Dzień 2 – Sieci (najczęściej sprawdzany temat)

**Linux (4 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| Model sieci | warstwy, IP/maska/CIDR, brama, ARP, MAC | rozpisz sieć labu: `192.168.180.0/24`, `.2`, `.10`, `.100–.120` |
| Interfejsy | `ip a`, `ip -br a`, `ip link set ... up/down`, `ethtool` | czemu `ens37` jest UP bez IP? |
| Routing | `ip route`, `ip route get 1.1.1.1`, `traceroute`/`tracepath` | którędy ruch wychodzi do internetu? |
| ARP / sąsiedzi | `ip neigh` | MAC bramy `.2` |
| DNS | `resolvectl status`, `dig +short`, `nslookup`, `/etc/hosts`, `/etc/resolv.conf` | skąd VM bierze DNS? |
| Porty | `ss -tulpn`, `ss -tnp`, `lsof -i :5000`, `nc -zv host port`, `curl -v` | które kontenery słuchają na 5000, 8774, 9696? |
| Podgląd ruchu | `tcpdump -i <if> -nn icmp`, `tcpdump port 22`, `-w plik.pcap` | złap ping do floating IP – na którym interfejsie go widać? |
| Firewall | `iptables -L -n -v`, `iptables -t nat -L`, `nft list ruleset`, `ufw status` | reguła NAT floating IP w namespace routera |
| Namespace'y | `ip netns list`, `ip netns exec <ns> ip a` | wejdź do `qrouter-...`, ping do instancji |
| Mosty i OVS | `bridge link`, `ovs-vsctl show` | `br-ex` → `ens37`; `br-int` → instancje |
| Konfiguracja | `/etc/netplan/*.yaml`, `netplan try`, `netplan apply` | czym `try` różni się od `apply`? |

**Pytania kontrolne:** „nie działa strona” – kolejność diagnozy (link → IP → brama → DNS → port → firewall)?
Czym jest `/24`? Co robi NAT?

**OpenStack (2 h)** – ćw. 4: własna sieć, podsieć, router, security group; floating IP = NAT w namespace routera.

---

## Dzień 3 – Dyski, użytkownicy, uprawnienia

**Linux (4 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| Dyski i partycje | `lsblk`, `blkid`, `fdisk -l`, `parted -l` | `sda`, `sdb`, partycje, `sr0` |
| Miejsce | `df -h`, `df -i`, `du -sh /var/lib/docker/*`, `ncdu` | co zajmuje najwięcej miejsca? |
| LVM | `pvs`, `vgs`, `lvs`, `pvcreate`, `vgcreate`, `lvcreate`, `lvextend -r` | Twoja pułapka 49 GB – jak naprawić bez reinstalacji? |
| Systemy plików | `mkfs.ext4`, `mkfs.xfs`, `mount`, `umount`, `findmnt`, `/etc/fstab` (UUID!) | sformatuj i zamontuj wolumen Cindera **w instancji** |
| Swap | `swapon --show`, `free -h` | ile swapu ma VM? |
| Użytkownicy i grupy | `id`, `groups`, `useradd -m`, `usermod -aG`, `passwd`, `/etc/passwd`, `/etc/shadow` | dodaj użytkownika `test` do grupy `docker` |
| sudo | `/etc/sudoers.d/`, `visudo`, `sudo -l` | co dodał `install-aio.sh` i czemu to tylko lab? |
| Uprawnienia | `chmod 755/644/600`, `chmod u+x`, `chown user:grupa`, `umask`, SUID/SGID/sticky bit | czemu `/tmp` ma `t`? czemu `passwords.yml` ma 600? |
| ACL | `getfacl`, `setfacl` | daj jednemu użytkownikowi odczyt pliku bez zmiany grupy |

**Pytania kontrolne:** hard link vs soft link? Dysk pełny, a `du` mówi mniej – dlaczego (`lsof +L1`)?
Co to inode? Jak powiększyć `/` bez restartu?

**OpenStack (2 h)** – ćw. 5 (Cinder: wolumen = LV w `cinder-volumes`, iSCSI), ćw. 6 (obraz Ubuntu + cloud-init).

---

## Dzień 4 – Diagnoza, wydajność, kontenery, start systemu

**Linux (4 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| Obciążenie | `uptime` (load average), `top`, `htop`, `vmstat 1`, `mpstat` | load przy uruchamianiu 3 instancji naraz |
| Pamięć | `free -h`, `/proc/meminfo`, OOM killer w `dmesg` | co to „buff/cache” i czemu to nie problem? |
| Dysk I/O | `iostat -x 1`, `iotop` | który proces najbardziej pisze na dysk? |
| Analiza logów | `grep -E`, `awk`, `sort \| uniq -c \| sort -rn \| head` | 5 najczęstszych błędów w logach Novy |
| Otwarte pliki | `lsof -p PID`, `lsof +L1`, `fuser -v` | kto trzyma port 80? |
| Sygnały | `kill -15` vs `-9`, `kill -HUP`, `trap` | czemu `-9` to ostateczność? |
| Docker | `docker ps -a`, `logs --tail`, `inspect`, `exec -it`, `stats`, `system df` | gdzie jest config kontenera `nova_compute`? |
| KVM / libvirt | `lsmod \| grep kvm`, `virsh list --all`, `virsh dumpxml` | znajdź instancję w libvirt |
| Start systemu | UEFI → GRUB → jądro → initramfs → systemd → target; `systemd-analyze blame` | co startuje najdłużej? |
| Tryb awaryjny | GRUB `e` → `systemd.unit=rescue.target`, reset hasła roota | (na snapshocie!) odzyskaj dostęp bez hasła |

**Pytania kontrolne:** serwer „zwolnił” – 5 pierwszych poleceń? Load 4.0 na 8 CPU – dużo?
Proces zombie vs sierota?

**OpenStack (2 h)** – ćw. 8 (psucie i naprawa: zatrzymany kontener, instancja w ERROR, logi `/var/log/kolla`),
ćw. 9 (zmiana w `globals.yml` → `kolla-ansible reconfigure`).

---

## Dzień 5 – Bash, SSH, bezpieczeństwo

**Linux (4 h)**

| Temat | Polecenia | Ćwiczenie w labie |
|---|---|---|
| Bash – podstawy | zmienne, `"$var"`, `$(...)`, `$?`, `if`, `[[ ]]`, `for`, `while`, `case`, funkcje | przeczytaj `install-aio.sh` i wyjaśnij każdą sekcję |
| Bash – porządnie | `set -euo pipefail`, `trap`, `shellcheck`, argumenty `$1 $@`, `getopts` | dlaczego skrypt ma `set -euo pipefail`? |
| Własny skrypt | – | **health check**: usługi OpenStack, kontenery unhealthy, wolne miejsce, load → raport |
| cron / timery | `crontab -e`, składnia `*/5 * * * *`, `systemctl list-timers` | uruchamiaj health check co 5 min, wynik do logu |
| SSH | `ssh-keygen`, `authorized_keys`, `~/.ssh/config`, `scp`, `rsync -av`, tunel `-L` | logowanie kluczem; tunel do Horizon |
| Utwardzanie | `sshd_config` (`PasswordAuthentication no`, `PermitRootLogin no`), `ufw`, `fail2ban` | co zmienisz przed wystawieniem serwera? |
| Pakiety | `apt update/upgrade`, `apt show`, `apt-cache policy`, `dpkg -l`, `dpkg -L` | skąd pochodzi `docker-ce`? |
| Rotacja logów | `/etc/logrotate.d/`, `logrotate -d` | czemu logi nie zapełniają dysku? |

**Pytania kontrolne:** co robi `set -euo pipefail`? Klucz publiczny vs prywatny – który gdzie leży?

**OpenStack (2 h)** – teoria produkcji (HA: 3 kontrolery, Galera, RabbitMQ, VIP; Ceph; OpenStack vs VMware) +
próbna rozmowa (pytania z `cwiczenia.md`).

---

## Pytania z Linuksa na rozmowę

1. Co się dzieje od włączenia serwera do ekranu logowania?
2. Proces vs wątek; zombie vs sierota.
3. Jak sprawdzisz, kto słucha na porcie 443?
4. Hard link vs soft link.
5. Co to load average i czy 4.0 to dużo?
6. Dysk 100%, a `du` pokazuje mniej – dlaczego?
7. Jak dodać miejsce na `/` bez restartu?
8. `chmod 755` vs `644` – co znaczą liczby? Co to sticky bit?
9. Jak bezpiecznie zmienić sieć na zdalnym serwerze?
10. Strona nie działa – jak diagnozujesz krok po kroku?
11. `kill -9` vs `kill -15`.
12. Jak znaleźć pliki większe niż 1 GB zmienione w ostatniej dobie?
13. Co to systemd unit i jak napisać własną usługę?
14. Jak działa logowanie kluczem SSH?
15. Co to network namespace i gdzie go używa Docker / OpenStack / Kubernetes?
