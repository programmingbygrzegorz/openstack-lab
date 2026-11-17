# Ćwiczenia na labie + pytania na rozmowę

Przed każdą sesją na VM:
```bash
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
```

`init-runonce` utworzył już: obraz **cirros**, sieć zewnętrzną **public1**, sieć **demo-net** (10.0.0.0/24), router **demo-router**, flavory **m1.\***, klucz **mykey** i reguły ICMP/SSH w security group **default** projektu admin.

---

## 1. Rozpoznanie: co tu w ogóle działa

```bash
openstack service list              # usługi w katalogu Keystone
openstack endpoint list             # adresy API (public/internal/admin)
openstack compute service list      # nova-scheduler, nova-conductor, nova-compute
openstack network agent list        # agenci Neutron (OVS, L3, DHCP, metadata)
openstack volume service list       # cinder-scheduler, cinder-volume
openstack hypervisor list
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
sudo ls /var/log/kolla/             # logi każdej usługi (skrót do wolumenu kolla_logs)
ls /etc/kolla/                      # konfiguracja wygenerowana przez Kolla
```
**Zrozum:** która usługa za co odpowiada (tabela na końcu).

## 2. Pierwsza instancja (VM) + floating IP

```bash
openstack server create --image cirros --flavor m1.tiny \
  --network demo-net --key-name mykey vm1
openstack server list                       # czekaj na ACTIVE
openstack floating ip create public1
openstack server add floating ip vm1 <FLOATING_IP>
ping <FLOATING_IP>
ssh -i ~/.ssh/id_ecdsa cirros@<FLOATING_IP>   # hasło cirros: gocubsgo
openstack console log show vm1
```
Spróbuj też pingu do floating IP **z Windowsa** (PowerShell).

**Zrozum:** droga pakietu: VM → demo-net → router (SNAT/DNAT) → public1 → VMnet8 → Windows.

## 3. Projekt i użytkownik (Keystone)

```bash
openstack project create --description "Projekt testowy" dev
openstack user create --project dev --password Haslo123 jan
openstack role add --project dev --user jan member
openstack role assignment list --project dev --names
openstack quota set --instances 3 --cores 4 --ram 4096 dev
openstack quota show dev
```
Zaloguj się do Horizon jako `jan` i zobacz, czym różni się widok od widoku admina.

## 4. Własna sieć od zera (Neutron) – najważniejsze ćwiczenie

```bash
openstack network create net-app
openstack subnet create --network net-app --subnet-range 172.16.10.0/24 \
  --dns-nameserver 1.1.1.1 subnet-app
openstack router create r-app
openstack router set --external-gateway public1 r-app
openstack router add subnet r-app subnet-app

openstack security group create sg-web
openstack security group rule create --proto tcp --dst-port 22 sg-web
openstack security group rule create --proto tcp --dst-port 80 sg-web
openstack security group rule create --proto icmp sg-web

openstack server create --image cirros --flavor m1.tiny --network net-app \
  --security-group sg-web --key-name mykey web1
```
Dodaj floating IP i sprawdź, czy działa. Potem **usuń regułę ICMP** i zobacz, że ping przestaje działać.

**Podgląd „pod maską”:**
```bash
sudo ip netns                                  # qrouter-*, qdhcp-* (namespaces)
sudo ip netns exec qrouter-<ID> ip a           # interfejsy routera
sudo ip netns exec qrouter-<ID> iptables -t nat -S   # reguły SNAT/DNAT floating IP
sudo docker exec openvswitch_vswitchd ovs-vsctl show # mosty br-int, br-ex, br-tun
```

## 5. Wolumeny (Cinder)

```bash
openstack volume create --size 1 vol1
openstack server add volume vm1 vol1
openstack volume list
sudo lvs cinder-volumes          # wolumen to po prostu LV na dysku sdb
```
W VM: `sudo fdisk -l` pokaże nowy dysk `/dev/vdb`. Potem snapshot wolumenu:
```bash
openstack volume snapshot create --volume vol1 --force snap1
```

## 6. Obrazy (Glance)

Ściągnij na VM obraz Ubuntu cloud (~600 MB) i wgraj go:
```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
openstack image create --disk-format qcow2 --container-format bare \
  --file noble-server-cloudimg-amd64.img --public ubuntu-24.04
openstack flavor create --vcpus 2 --ram 2048 --disk 10 m1.ubuntu
```
Uruchom z niego VM (`--flavor m1.ubuntu`) i zaloguj się jako `ubuntu`. Przekaż mu skrypt przez **cloud-init** (`--user-data plik.yaml`), np. instalujący nginx.

## 7. Operacje na instancjach

```bash
openstack server stop vm1 && openstack server start vm1
openstack server resize --flavor m1.small vm1     # potem: resize confirm
openstack server image create --name vm1-snap vm1 # snapshot instancji -> obraz
openstack server rebuild --image cirros vm1
openstack server event list vm1                   # historia akcji
```

## 8. Diagnostyka – celowo zepsuj i napraw

| Zepsuj | Obserwuj | Napraw |
|---|---|---|
| `sudo docker stop nova_compute` | `openstack compute service list` → down; nowa VM → ERROR „No valid host” | `sudo docker start nova_compute` |
| `sudo docker stop rabbitmq` | API zwraca błędy/timeouty, logi `sudo tail /var/log/kolla/nova/*.log` | `sudo docker start rabbitmq` |
| Utwórz VM z flavorem 64 GB RAM | `openstack server show` → fault: *No valid host* | Zrozum rolę nova-scheduler i placement |
| `sudo docker stop neutron_dhcp_agent` | Nowa VM nie dostaje IP (console log) | `sudo docker start neutron_dhcp_agent` |

## 9. Operacje Kolla (tym zajmujesz się w pracy)

```bash
# zmiana konfiguracji usługi – np. overcommit CPU
sudo mkdir -p /etc/kolla/config/nova
echo -e "[DEFAULT]\ncpu_allocation_ratio = 4.0" | sudo tee /etc/kolla/config/nova/nova.conf
kolla-ansible reconfigure -i ~/all-in-one --tags nova

# włączenie nowej usługi, np. Heat dashboard / Octavia / Magnum – w globals.yml, potem:
kolla-ansible deploy -i ~/all-in-one

kolla-ansible -h        # upgrade, stop, destroy, mariadb_recovery, certificates...
```

---

# Pytania na rozmowę (przygotuj własne odpowiedzi)

## Podstawowe usługi

| Usługa | Projekt | Jednym zdaniem |
|---|---|---|
| Identity | **Keystone** | Logowanie, tokeny, projekty, role, katalog endpointów |
| Compute | **Nova** | Tworzenie i życie VM-ek (api, scheduler, conductor, compute) |
| Placement | **Placement** | Ewidencja zasobów (CPU/RAM/dysk) dla schedulera |
| Network | **Neutron** | Sieci, podsieci, routery, floating IP, security groups |
| Image | **Glance** | Obrazy systemów |
| Block storage | **Cinder** | Wolumeny (dyski) podpinane do VM |
| Object storage | **Swift** / Ceph RGW | Obiekty (jak S3) |
| Dashboard | **Horizon** | GUI |
| Orchestration | **Heat** | Infrastruktura jako kod (szablony HOT) |
| Load balancer | **Octavia** | LBaaS |
| Wspólne | **MariaDB/Galera, RabbitMQ, Memcached** | Baza, kolejka komunikatów, cache tokenów |

## Pytania

1. Opisz, co się dzieje krok po kroku po `openstack server create` (Keystone → nova-api → scheduler/placement → conductor → compute → Glance, Neutron, Cinder → libvirt/KVM).
2. Różnica między siecią **provider** a **self-service (tenant)**? Czym jest **floating IP** i jak działa (NAT na routerze)?
3. VXLAN vs VLAN vs flat – kiedy co?
4. **OVS vs OVN** – czym się różnią? (OVN to nowszy, rozproszony backend; coraz częstszy domyślny wybór.)
5. Security group vs firewall (FWaaS)? Gdzie fizycznie są stosowane reguły?
6. Wolumen Cinder vs dysk efemeryczny – co znika po usunięciu VM?
7. Jak wygląda HA kontrolerów? (3 węzły, Galera, RabbitMQ w klastrze/quorum queues, HAProxy + keepalived z VIP.) Czemu 3, a nie 2? (quorum, split-brain)
8. Dlaczego Ceph jest popularny z OpenStackiem? (jeden backend dla Glance, Cinder, Nova, copy-on-write klonowanie obrazów, live migration bez kopiowania dysku)
9. Live migration vs cold migration vs evacuate?
10. Instancja w stanie ERROR / „No valid host” – jak debugujesz? (`server show` fault, logi scheduler/conductor/compute, placement, quota)
11. VM nie dostaje IP / nie ma internetu – gdzie szukasz? (DHCP agent, namespace qdhcp, security group, router, MTU w VXLAN)
12. Jak robisz upgrade OpenStacka w Kolla? (zmiana wersji, `kolla-ansible pull`, `upgrade`, kolejność, backup bazy, test na stagingu)
13. Jak zmieniasz konfigurację usługi w Kolla? (`/etc/kolla/config/<usługa>/…` + `reconfigure`)
14. Jak monitorujesz chmurę? (Prometheus + exportery, Grafana, OpenSearch/centralne logi)
15. Overcommit CPU/RAM – co to `cpu_allocation_ratio`, `ram_allocation_ratio`?
16. Czym jest cloud-init i metadata service (169.254.169.254)?
17. Jak wydajesz dostęp zespołom? (projekty, role, quotas, ewentualnie domeny i federacja LDAP/SSO)

## Jak opowiadać o labie

> „Postawiłem OpenStacka przez Kolla-Ansible na Ubuntu 24.04 (all-in-one, nested KVM w VMware). Skonfigurowałem sieci provider i self-service na Open vSwitch, Cindera na LVM, przećwiczyłem pełny cykl życia instancji, floating IP, security groups, projekty i quoty. Celowo psułem usługi (nova-compute, RabbitMQ, DHCP agent) i diagnozowałem po logach i namespace'ach. Zmieniałem konfigurację przez `reconfigure`. Następny krok to multinode z osobnymi compute i Ceph.”

Mów tylko o tym, co **naprawdę** zrobiłeś: dopytają o szczegóły.
