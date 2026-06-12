# Unraid PXE Server (custom iPXE stack, proxyDHCP)

A self-hosted PXE boot server for Unraid built from:

- **dnsmasq** — proxyDHCP responder + TFTP server (coexists with your router's DHCP, no router changes needed)
- **nginx** — HTTP server for iPXE menus, kernels, and your ISOs
- **iPXE** — the bootloader and menu system
- **netboot.xyz** — available as a submenu entry for downloading/booting any OS online

Works with both **UEFI** and **Legacy BIOS** clients (auto-detected per client).

## How it works

1. A client PXE-boots and gets its IP from your **existing router** as usual.
2. dnsmasq (in proxyDHCP mode) chimes in with only the PXE boot info: "fetch `undionly.kpxe` (BIOS) or `ipxe.efi` (UEFI) from my TFTP."
3. The client runs iPXE, which re-requests DHCP. dnsmasq detects iPXE and now answers: "chain `http://UNRAID_IP:8080/boot.ipxe`."
4. iPXE downloads the menu over HTTP and shows it. Everything big (kernels, ISOs) travels over fast HTTP instead of TFTP.

## Setup on Unraid

### 1. Copy this folder to Unraid

Place the whole `pxe-server/` folder at:

```
/mnt/user/appdata/pxe-server/
```

### 2. Configure `.env`

Edit `.env` and set:

| Variable | Meaning | Example |
|----------|---------|---------|
| `UNRAID_IP` | Static LAN IP of your Unraid server | `192.168.1.10` |
| `SUBNET` | Your LAN network address | `192.168.1.0` |
| `HTTP_PORT` | HTTP port (80 is used by Unraid's UI) | `8080` |

### 3. Download the iPXE bootloaders (one time)

From the Unraid terminal:

```sh
cd /mnt/user/appdata/pxe-server
sh setup.sh
```

This fetches `undionly.kpxe`, `ipxe.efi`, and `snponly.efi` into `tftp/`.

### 4. Point it at your ISOs

The compose file bind-mounts `/mnt/user/isos` (read-only) into the web server
as `http://UNRAID_IP:8080/isos/`. If your ISO share has a different path, edit
the volume line in `docker-compose.yml`.

Then add menu entries for your ISOs in `http/menus/local.ipxe` (templates and
examples are included in that file). Changes take effect immediately — no
container restart needed, menus are fetched fresh on every boot.

### 5. Start the stack

Either install the **Compose Manager** plugin (Apps tab) and add this folder
as a stack, or from the Unraid terminal:

```sh
cd /mnt/user/appdata/pxe-server
docker compose up -d
```

### 6. Boot a client

Enable network/PXE boot in the client's firmware and boot. You should see the
menu within a few seconds.

## Verifying it works

From another machine on the LAN:

```sh
# TFTP serving the bootloader? (UDP 69)
tftp 192.168.1.10 -c get undionly.kpxe

# HTTP serving the menu?
curl http://192.168.1.10:8080/boot.ipxe

# Browse your ISOs
# open http://192.168.1.10:8080/isos/ in a browser
```

Watch dnsmasq's view of PXE requests:

```sh
docker logs -f pxe-dnsmasq
```

Best first test: an Unraid VM (or any VM on the LAN with bridged networking)
set to network boot — try once with OVMF (UEFI) and once with SeaBIOS.

## Adding your own ISO menu entries

Open `http/menus/local.ipxe`. Two patterns are provided:

1. **`sanboot` (memdisk-free, simplest)** — works for many modern hybrid/live
   ISOs (GParted, Clonezilla, many rescue tools):

   ```
   sanboot ${http-root}/isos/gparted-live.iso
   ```

2. **Extract kernel/initrd (most reliable for installers)** — extract
   `vmlinuz` + `initrd` from the ISO into `http/boot/<name>/`, then boot them
   and pass the ISO URL as a kernel argument. Examples for Ubuntu and Debian
   are included in `local.ipxe`.

For **Windows** installers you need `wimboot` — easiest path is to just use
the netboot.xyz menu entry, which handles that for you.

## Known caveats

- **Secure Boot**: iPXE binaries are unsigned, so disable Secure Boot on
  clients. (The alternative — a signed shim chain — is significantly more
  work and not included here.)
- **Not every ISO sanboots.** UEFI in particular is picky about `sanboot`.
  If an ISO hangs or errors, use the extract-kernel/initrd pattern instead.
- **Host networking is required.** dnsmasq must see LAN DHCP broadcasts
  (UDP 67/68) and serve TFTP (UDP 69) + proxyDHCP (UDP 4011). Both containers
  run with `network_mode: host`. If your LAN uses VLANs, the PXE clients must
  be on the same L2 segment/VLAN as the Unraid server (DHCP broadcasts don't
  cross VLANs without a relay).
- **Two PXE servers on one LAN** will conflict — make sure nothing else
  (e.g. your router, another netboot container) is answering PXE.
- **Port conflicts on the host**: nothing else on Unraid may bind UDP 69
  or TCP `HTTP_PORT`.

## Project layout

```
pxe-server/
  docker-compose.yml      # dnsmasq + nginx, host networking
  .env                    # UNRAID_IP, SUBNET, HTTP_PORT
  setup.sh                # one-time: fetch iPXE binaries into tftp/
  dnsmasq/
    dnsmasq.conf.template # proxyDHCP + TFTP config (envsubst'd at start)
  nginx/
    default.conf.template # HTTP server config (envsubst'd at start)
  tftp/                   # iPXE bootloaders (filled by setup.sh)
  http/                   # nginx web root
    boot.ipxe             # main menu
    menus/local.ipxe      # your local ISO entries
    boot/                 # extracted kernels/initrds go here
```
