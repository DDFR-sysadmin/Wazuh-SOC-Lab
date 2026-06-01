`
# Network Topology & Architecture (VMware NAT)

Этот документ описывает сетевую архитектуру SOC-лабы, развёрнутой в VMware. Все хосты изолированы внутри приватной подсети с выходом в интернет через NAT-шлюз.

## Схема сети (ASCII Topology)

```text
                     [ Internet ]
                          │
                  ( VMware NAT Gateway )
                    [ 10.0.0.2/24 ]
                          │
   ───────────────────────┴─────────────────────── ( Subnet: 10.0.0.0/24 )
         │                        │                        │
         ▼                        ▼                        ▼
  [ Attacker Node ]       [ Victim Server ]        [ SIEM/SOC Node ]
    Kali Linux              Win/Linux Server         Ubuntu Server
   IP: DHCP (NAT)           IP: DHCP (NAT)            IP: 10.0.0.10
                            (Apache + DVWA)          (Wazuh in Docker)

```

## Сетевые параметры подсети

-   **Сеть (Subnet):** `10.0.0.0/24`
    
-   **Шлюз по умолчанию (Gateway):** `10.0.0.2` (Виртуальный NAT-интерфейс VMware).
    
-   **DHCP диапазон:** Включен для динамических хостов.
    
-   **DNS Серверы:** `8.8.8.8`, `1.1.1.1` (Google / Cloudflare public resolvers).
    

## Таблица распределения IP-адресов (IPAM)


| Хост / Сервис | Операционная система | Тип IP | IP-адрес | Описание / Роль |
| :--- | :--- | :--- | :--- | :--- |
| **Wazuh Manager** | Ubuntu Server | Статика | `10.0.0.10` | Сервер мониторинга, Wazuh Indexer & Dashboard в Docker |
| **Web-Victim** | Windows Server | DHCP | Динамический` | Уязвимый веб-сервер Apache + DVWA под мониторингом Wazuh Agent |
| **Attacker** | Kali Linux | DHCP | Динамический | Машина пентестера для проведения атак (генерация логов) |

## Конфигурация сетевого интерфейса (Wazuh Node)

Для фиксации статического IP-адреса на сервере мониторинга (`10.0.0.10`) используется утилита **Netplan** так как это стандартная утилита управления сетями в Ubuntu Server 26.04. Конфигурационный файл сохранён в репозитории.

### 00-installer-config.yaml

YAML

```
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses:
        - 10.0.0.10/24
      routes:
        - to: default
          via: 10.0.0.2
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1

```
