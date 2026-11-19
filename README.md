# Lab OpenStack – all-in-one (Kolla-Ansible) na VMware Workstation Pro

Cały OpenStack na **jednej VM**. Kolejność: krok 1 → 6.

---

## Krok 1. Sprawdź sieć NAT w VMware

1. VMware → **Edit → Virtual Network Editor** (kliknij *Change Settings*, jeśli trzeba uprawnień admina).
2. Wybierz **VMnet8 (NAT)** i zapisz **Subnet IP**, np. `192.168.180.0`.
3. Kliknij **NAT Settings** i zapisz **Gateway IP** (zwykle `.2`, np. `192.168.180.2`).
4. Kliknij **DHCP Settings**: DHCP rozdaje zwykle `.128–.254`. Adresów poniżej `.128` używamy statycznie.

![Virtual Network Editor – VMnet8 (NAT) z podsiecią 192.168.180.0](docs/img/01-virtual-network-editor.png)

> Tylko odczytaj wartości i zamknij okno przyciskiem **Cancel**. Zmiana bramy lub DHCP odetnie inne VM-ki w tej sieci.

Ten lab używa podsieci VMnet8 `192.168.180.0/24` i wszystkie pliki są już pod nią ustawione.
Jeśli Twoja VMnet8 ma inną podsieć, zamień `192.168.180.` we wszystkich plikach na swoją.

| Adres | Do czego |
|---|---|
| `192.168.180.2` | brama VMware NAT |
| `192.168.180.10` | VM z OpenStackiem (Horizon, API) |
| `192.168.180.51–55` | **zajęte** – węzły k3s (Kubernetes) |
| `192.168.180.100–120` | pula floating IP dla instancji OpenStacka |
| `192.168.180.128–254` | DHCP VMware – nie używać statycznie |

> ⚠️ Jeśli w tej samej sieci VMnet8 masz inne VM-ki (np. Kubernetes), sprawdź, że nie używają
> adresów `.10` ani `.100–120` – także w pulach load balancera (MetalLB).

---

## Krok 2. Utwórz VM

**File → New Virtual Machine → Custom**

| Ustawienie | Wartość |
|---|---|
| ISO | Ubuntu Server **24.04 LTS** |
| vCPU | 8 (np. 1 procesor × 8 rdzeni; minimum 4) |
| RAM | **16 GB** (można 20–24 GB, masz 64 GB) |
| Dysk 1 | **100 GB** (system + kontenery) |
| Dysk 2 | **50 GB** (dla Cindera, czyli wolumenów); dodaj go w ustawieniach VM, zostaw nieużywany |
| Karta sieciowa 1 | **NAT (VMnet8)** – zarządzanie |
| Karta sieciowa 2 | **NAT (VMnet8)** – sieć zewnętrzna Neutrona, **bez IP** |
| Procesor | ✅ **Virtualize Intel VT-x/EPT or AMD-V/RVI** |

> Obie karty są w tej samej sieci NAT. Dzięki temu floating IP instancji (`192.168.180.100+`) będą osiągalne bezpośrednio z Windowsa (ping, SSH).

**Kolejność w kreatorze:**

1. *Custom (advanced)* → *Hardware compatibility*: domyślne.
2. *Installer disc image file (iso)*: wskaż ISO Ubuntu Server 24.04.

   > ⚠️ **Dokładnie 24.04, nie nowsze (np. 26.04).** Kolla-Ansible 2026.1 i 2026.2 wspierają z Ubuntu tylko 24.04 ([support matrix](https://docs.openstack.org/kolla-ansible/latest/user/support-matrix.html)). Na 26.04 instalacja odpadnie na `prechecks`. Wersję sprawdzisz w VM: `grep PRETTY /etc/os-release`.
3. *Name*: `openstack-aio` (taką samą nazwę daj potem jako hostname w Ubuntu).
4. *Processors*: 1 × 8 rdzeni, *Memory*: 16384 MB, *Network*: NAT.
5. *Disk*: **Create a new virtual disk**, SCSI, **100 GB**, ☐ *Allocate all disk space now* (puste – plik rośnie stopniowo), **Store virtual disk as a single file**.
6. Na ostatnim ekranie **nie klikaj od razu Finish** – najpierw **Customize Hardware…**

**Customize Hardware:**

- **Processors** → zaznacz ☑ **Virtualize Intel VT-x/EPT or AMD-V/RVI** (pozostałe dwa pola puste):

  ![Processors: 1 procesor × 8 rdzeni, zaznaczone Virtualize Intel VT-x/EPT](docs/img/02-procesor-vtx.png)

- **Add… → Hard Disk** → SCSI → nowy dysk **50 GB**, single file, bez prealokacji (dla Cindera).
- **Add… → Network Adapter** → **NAT** (druga karta, dla floating IP).
- *Sound Card* możesz usunąć (**Remove**) – serwer jej nie potrzebuje.

> ⚠️ Sprawdź, czy na liście urządzeń jest **Hard Disk 100 GB**. Jeśli go brakuje (zależnie od wersji VMware pojawia się
> dopiero po *Finish*), dodaj go przez **Add… → Hard Disk**. Bez dysku Ubuntu się nie zainstaluje.

**Dysk wyszedł za mały (np. domyślne 20 GB)?** Póki Ubuntu nie jest zainstalowane, wystarczy go powiększyć:
VM → **Settings → Hard Disk (SCSI) → Expand…** → wpisz **100** → **Expand**.

![Ustawienia dysku: przycisk Expand… do powiększenia dysku z 20 GB do 100 GB](docs/img/03-dysk-expand.png)

Nazwę VM zmienisz w zakładce **Options → Virtual machine name** (np. z „Ubuntu 64-bit” na `openstack-aio`).

Docelowa lista urządzeń:

```
Memory              16 GB
Processors          8   (VT-x ☑)
Hard Disk (SCSI)    100 GB
New Hard Disk       50 GB
CD/DVD (SATA)       ubuntu-24.04-live-server-amd64.iso
Network Adapter     NAT
Network Adapter 2   NAT
```

![Gotowa lista urządzeń: 16 GB RAM, 8 procesorów, dyski 100 GB i 50 GB, dwie karty NAT](docs/img/04-gotowa-lista-urzadzen.png)

---

## Krok 2b. Windows blokuje VT-x (Hyper-V / VBS)

Na Windows 11 przy pierwszym starcie VM często pojawia się jeden z komunikatów:

- *„Feature 'hv.capable' was 0, but must be at least 0x1”*
- *„Virtualized Intel VT-x/EPT is not supported on this platform. Continue without…?”* → kliknij **No**

![VMware: Virtualized Intel VT-x/EPT is not supported on this platform](docs/img/05-blad-vtx-not-supported.png)

### Dlaczego

Procesor ma jedną funkcję wirtualizacji (VT-x) i może z niej korzystać tylko jeden „szef”.
Windows 11 domyślnie uruchamia **własny hypervisor** i zamyka w nim sam siebie (**VBS** – zabezpieczenia
oparte na wirtualizacji). VMware jest wtedy tylko „lokatorem” i nie może przekazać VT-x dalej do VM.
Bez tego Ubuntu w VM nie uruchomi KVM, a instancje OpenStacka będą bardzo wolne (emulacja qemu).

```
Teraz:      Procesor → Hypervisor Windowsa → Windows + VMware → VM (bez VT-x)
Po zmianie: Procesor → VMware → VM openstack-aio → KVM → instancje OpenStacka
```

### Sprawdź stan (PowerShell, bez uprawnień admina)

```powershell
(Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard).VirtualizationBasedSecurityStatus
(Get-CimInstance Win32_ComputerSystem).HypervisorPresent
```

`2` / `True` = blokada aktywna. `0` / `False` = można uruchamiać VM z VT-x.

### Jak wyłączyć

**Sposób 1 (GUI):** Start → *Zabezpieczenia Windows* → *Zabezpieczenia urządzenia* → *Szczegóły izolacji rdzenia* →
**Integralność pamięci: Wył.** → restart komputera.

**Sposób 2 (gdy przełącznik jest szary lub wraca na „Wł.”):** *Terminal (administrator)*:

```powershell
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f
bcdedit /set hypervisorlaunchtype off
```

| Polecenie | Co robi |
|---|---|
| `reg add ... Enabled /d 0` | Wyłącza **integralność pamięci** (HVCI) – to ona wymaga hypervisora Windowsa |
| `bcdedit /set hypervisorlaunchtype off` | Zakazuje ładowania hypervisora przy starcie – niezależnie od tego, co by go chciało (WSL2, Docker Desktop, Sandbox, Credential Guard) |

Potem **restart** – hypervisor ładuje się przed Windowsem, więc zmiana działa dopiero po ponownym uruchomieniu.

> Przed restartem wyłącz poprawnie inne działające VM-ki (`sudo poweroff`), a najlepiej zrób im snapshot.
> Pliki VM-ek, sieć VMnet8 i adresy IP się nie zmieniają – inne laby (np. k3s) działają dalej, zwykle szybciej.

### ⚠️ Zagrożenia i skutki wyłączenia

| Co tracisz / co się zmienia | Co to znaczy w praktyce | Jak ograniczyć ryzyko |
|---|---|---|
| **Integralność pamięci (HVCI)** | Windows przestaje pilnować, czy sterowniki ładowane do jądra są zaufane. Złośliwy albo podatny sterownik (np. dołączony do cheatów, „crackowanych” programów, starych narzędzi) łatwiej przejmie pełną kontrolę nad systemem. | Instaluj sterowniki i programy tylko z oficjalnych źródeł; nie uruchamiaj crackowanego oprogramowania. |
| **VBS** – izolacja wrażliwych części systemu | Słabsza ochrona przed złośliwym oprogramowaniem, które już działa z uprawnieniami admina (np. trudniej mu było manipulować jądrem). | Pracuj na zwykłym koncie, nie na koncie administratora; nie wyłączaj UAC. |
| **Credential Guard** (jeśli był włączony – zwykle w wersjach firmowych) | Hasła i tokeny logowania w pamięci są łatwiej dostępne dla narzędzi typu „mimikatz” po przejęciu komputera. | Na komputerze służbowym **nie wyłączaj** tych zabezpieczeń bez zgody działu IT. |
| **WSL2, Docker Desktop, Windows Sandbox, Hyper-V** | Przestają działać (potrzebują hypervisora Windowsa). | Włączaj hypervisor z powrotem, gdy ich potrzebujesz. |
| **Gry z anti-cheatem / niektóre programy bankowe lub firmowe** | Część z nich wymaga VBS/HVCI i może odmówić uruchomienia. | Cofnij zmianę na czas korzystania z nich. |
| **Zgodność z polityką firmy** | Na laptopie służbowym to często naruszenie zasad bezpieczeństwa. | Rób lab na prywatnym komputerze. |

Co **nie** jest zagrożone: Twoje pliki, programy, antywirus (Microsoft Defender działa dalej), zapora, aktualizacje Windows.
Tak działał domyślnie Windows 10 – to nie jest stan „bez ochrony”, tylko bez jednej z jej warstw.

### Jak cofnąć (gdy skończysz z labem)

GUI: **Integralność pamięci: Wł.** albo w *Terminal (administrator)*:

```powershell
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 1 /f
bcdedit /set hypervisorlaunchtype auto
```

i restart. VM z zaznaczonym VT-x przestanie wtedy startować – przy następnym labie wyłącz ponownie.

### Komunikat „side channel mitigations” – to nie błąd

![Informacja VMware o side channel mitigations](docs/img/06-side-channel-hint.png)

To tylko informacja, że VM działa z ochroną przed atakami na procesor (Spectre/Meltdown) kosztem odrobiny wydajności.
Kliknij **OK** (możesz zaznaczyć *Do not show this hint again*). Niczego nie zmieniaj.

---

## Krok 3. Instalacja Ubuntu

- Język angielski, standardowa instalacja **Ubuntu Server** (nie minimized).
- Sieć: na razie zostaw DHCP, skonfigurujemy ją w kroku 4.
- Dysk: **zaznacz tylko dysk 100 GB** (`sda`, nie `sdb` 50 GB – ten zostaje pusty dla Cindera). LVM może zostać włączone.
  Szyfrowania LUKS **nie zaznaczaj** – w labie wymagałoby hasła przy każdym starcie VM.

  ![Instalator Ubuntu: cały dysk /dev/sda 100 GB, LVM włączone, bez szyfrowania LUKS](docs/img/07-ubuntu-dysk-lvm.png)

- ⚠️ **Pułapka LVM:** w podsumowaniu `/` ma tylko **~49 GB**, a druga połowa dysku leży jako „dostępna przestrzeń” w `ubuntu-vg`.
  Kliknij `ubuntu-lv` → **Edytuj** → w polu rozmiaru wpisz maksimum (ok. **97.99G**) → Zapisz. Uważaj, żeby przy okazji nie zmienić nazwy woluminu.

  ![Pułapka: / = 48.996G, a w ubuntu-vg zostaje 49 GB wolnego](docs/img/08-ubuntu-lvm-pulapka-49g.png)
- **Profil:** nazwa serwera `openstack-aio`, użytkownik np. `student`.
- **Ubuntu Pro:** *Skip for now*.
- ✅ **Install OpenSSH server** (bez tego nie skopiujesz plików ani nie zalogujesz się przez SSH).
- **Snapy:** nic nie zaznaczaj – zwłaszcza **nie** Dockera (Kolla zainstaluje własnego).

> 💡 **Instalujesz ponownie, a VM od razu startuje stary system?** Esc zwykle nie zdąży.
> Wyłącz VM, w *Settings → CD/DVD* wskaż ISO i zaznacz *Connect at power on*, potem
> **VM → Power → Power On to Firmware → Boot Manager → EFI VMware Virtual SATA CDROM Drive**.

Po instalacji zaloguj się i sprawdź:

```bash
grep PRETTY /etc/os-release       # MUSI być Ubuntu 24.04 (nie 26.04!)
ip -br a                          # nazwy kart, np. ens33 i ens37
lsblk                             # drugi dysk, np. sdb 50G
egrep -c '(vmx|svm)' /proc/cpuinfo  # > 0 = nested KVM działa
df -h /                           # czy / ma ~95 GB
```

Jeśli `/` jest za mały (LVM zajął połowę dysku):
```bash
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
```

---

## Krok 4. Sieć (netplan)

Po instalacji obie karty mają tymczasowe adresy z DHCP (np. `ens33` = `.138`, `ens37` = `.139`).

**1. Skopiuj pliki – w PowerShellu na Windowsie** (na tymczasowy adres `ens33`):

```powershell
scp C:\Projekty\OpenStack\install-aio.sh C:\Projekty\OpenStack\netplan-aio.yaml student@192.168.180.138:~
```

> ⚠️ `scp` uruchamiasz **na Windowsie**, nie w sesji SSH na VM. Linux nie zna ścieżki `C:\...`
> i zwraca `Could not resolve hostname c`.

**2. Ustaw stały adres – najlepiej w konsoli VMware** (przez SSH połączenie się zawiesi, bo zmienia się IP):

```bash
sudo cp /etc/netplan/50-cloud-init.yaml ~/50-cloud-init.yaml.bak   # kopia zapasowa
sudo cp ~/netplan-aio.yaml /etc/netplan/50-cloud-init.yaml          # celowo nadpisujemy
sudo chmod 600 /etc/netplan/50-cloud-init.yaml
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo netplan apply
ip -br a     # ens33 = 192.168.180.10, ens37 = UP bez IP
ping -c 3 google.com
```

Dlaczego nadpisujemy, a nie dodajemy nowy plik: netplan **łączy** wszystkie pliki z `/etc/netplan/`,
więc stary plik dalej dawałby `ens37` adres z DHCP. Linia z `cloud-init` blokuje mu odtworzenie
starej konfiguracji przy restarcie.

**3. Od teraz łącz się z Windowsa przez SSH** (wygodniej niż konsola VMware):

```powershell
ssh student@192.168.180.10
```

> Po reinstalacji systemu SSH zgłosi `REMOTE HOST IDENTIFICATION HAS CHANGED` (nowy system = nowy klucz).
> Usuń stary wpis: `ssh-keygen -R 192.168.180.10`.

> 💡 Teraz zrób **snapshot VM** (VM → Snapshot → Take Snapshot, „czysty Ubuntu”). Jak coś się zepsuje, wracasz w 10 sekund.

---

## Krok 5. Instalacja OpenStacka

Na VM:

```bash
tmux new -s kolla           # sesja, która przeżyje zerwanie SSH
sed -i 's/\r$//' *.sh       # usuwa windowsowe końce linii, na wszelki wypadek
chmod +x *.sh
nano install-aio.sh         # popraw zmienne na górze pliku (karty, IP, sieć)
./install-aio.sh
```

Trwa to **40–90 minut** (pobieranie ok. 5–8 GB kontenerów, na dysku zajmą ok. 15–20 GB). Skrypt kończy się wypisaniem adresu Horizon i hasła admina.

**Po co `tmux`?** Bez niego zerwane połączenie SSH (uśpiony laptop, zamknięte okno) zabija instalację.
W tmux skrypt działa dalej. **Ctrl+B, potem D** – odłączasz się; `tmux attach -t kolla` – wracasz.

Postęp i błędy:

```bash
grep '===' ~/install-aio.log | tail -n 3    # na którym kroku (x/9)
tail -n 30 ~/install-aio.log                # ostatnie linie
```

Skrypt można bezpiecznie uruchomić ponownie po błędzie – pomija to, co już zrobione.

> 💡 Po udanej instalacji zrób **drugi snapshot** („OpenStack działa”).

---

## Krok 6. Pierwsze kroki

- **Horizon (GUI):** `http://192.168.180.10`, login `admin`, hasło wypisze skrypt
  (albo: `grep keystone_admin_password /etc/kolla/passwords.yml`).
- **CLI:**
  ```bash
  source ~/kolla-venv/bin/activate
  source /etc/kolla/admin-openrc.sh
  openstack service list
  ```
- Ćwiczenia krok po kroku: **`cwiczenia.md`**.

---

## Po restarcie VM

Kontenery startują same (Docker, `restart: unless-stopped`). Daj im 2–3 minuty. Jeśli coś nie działa:

```bash
sudo docker ps --filter health=unhealthy
sudo docker ps -a --filter status=exited
```

Po twardym wyłączeniu VM baza MariaDB (Galera) czasem nie wstaje sama. Wtedy:

```bash
source ~/kolla-venv/bin/activate
kolla-ansible mariadb_recovery -i ~/all-in-one
```

> Wyłączaj VM poprawnie (`sudo poweroff`), a nie „Power Off” w VMware.

## Najczęstsze problemy

| Objaw | Przyczyna / rozwiązanie |
|---|---|
| VMware: *„Virtualized Intel VT-x/EPT is not supported”* | Hyper-V/VBS w Windows – patrz **Krok 2b** (jak wyłączyć, zagrożenia, jak cofnąć). |
| Skrypt: *„Kolla-Ansible wspiera Ubuntu 24.04, a masz 26.04”* | Zainstalowano za nowe Ubuntu. Downgrade nie istnieje – przeinstaluj VM z ISO `ubuntu-24.04.x-live-server-amd64.iso` (patrz Krok 3). |
| VM startuje stary system zamiast instalatora z ISO | **VM → Power → Power On to Firmware → Boot Manager → CDROM** (Krok 3). |
| `scp`: `Could not resolve hostname c` | `scp` uruchomiony w VM zamiast w PowerShellu na Windowsie. Wpisz `exit` i powtórz. |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | System przeinstalowany, ma nowy klucz SSH: `ssh-keygen -R <adres>` na Windowsie. |
| SSH zawiesza się po `netplan apply` | Normalne – VM zmieniła adres. Połącz się na `192.168.180.10`. |
| `ens37` ma adres IPv4 po netplanie | Stary plik netplan dalej działa albo nie było `netplan apply`. Sprawdź `ls /etc/netplan/`, potem `sudo reboot`. |
| `Failed to install Ansible collections ... The read operation timed out` | Ansible Galaxy nie odpowiedziało na czas (problem serwera, nie labu). Uruchom `./install-aio.sh` ponownie – skrypt ma dłuższy timeout i 3 podejścia, a już zrobione kroki pomija. |
| `prechecks`: *Checking docker SDK version* → `No module named 'docker'` | Brak Docker SDK w venv: `source ~/kolla-venv/bin/activate && pip install docker dbus-python`, potem ponownie `./install-aio.sh` (aktualna wersja skryptu robi to sama). |
| Instalacja przerwana w połowie | Skrypt można uruchomić ponownie – nie nadpisze haseł ani grupy LVM `cinder-volumes`. |
| `prechecks` wywala się na interfejsie | Zła nazwa karty w `install-aio.sh` albo ens37 nie jest `UP`. |
| Instancja w stanie **ERROR** | `openstack server show <nazwa>` (pole *fault*), logi: `sudo less /var/log/kolla/nova/nova-compute.log`. |
| Nie ma pingu do floating IP | Security group bez reguły ICMP/SSH (init-runonce je dodaje do projektu admin), albo zła pula w `EXT_*`. |
| Brak miejsca | `df -h`; obrazy Dockera zajmują ~20–30 GB. |
| Chcę zacząć od nowa | Wróć do snapshotu albo: `kolla-ansible destroy -i ~/all-in-one --yes-i-really-really-mean-it` |
