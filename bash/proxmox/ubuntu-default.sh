# Baixar o user-data.yaml do GitHub
CLOUDINIT_YAML_URL="https://raw.githubusercontent.com/wallacedefreitas/bashscripts/refs/heads/main/cloudinit/user-default.yaml"
CLOUDINIT_YAML_FILE="user-data-$VMID.yaml"
wget -O /var/lib/vz/snippets/$CLOUDINIT_YAML_FILE "$CLOUDINIT_YAML_URL"

# Baixar o network-config.yaml do GitHub
CLOUDINIT_NET_URL="https://raw.githubusercontent.com/wallacedefreitas/bashscripts/refs/heads/main/cloudinit/network-default.yaml"
CLOUDINIT_NET_FILE="network-config-$VMID.yaml"
wget -O /var/lib/vz/snippets/$CLOUDINIT_NET_FILE "$CLOUDINIT_NET_URL"


echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
NEXTID=$(pvesh get /cluster/nextid)

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
HA=$(echo "\033[1;34m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    msg_error "This script will not work with PiMox! \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "⚠  User exited script \n"
  exit
}

function default_settings() {
  VMID="$NEXTID"
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_CACHE=""
  HN="ubuntu-lts-default"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  echo -e "${DGN}Using Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${DGN}Using Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DGN}Using Disk Cache: ${BGN}None${CL}"
  echo -e "${DGN}Using Hostname: ${BGN}${HN}${CL}"
  echo -e "${DGN}Using CPU Model: ${BGN}KVM64${CL}"
  echo -e "${DGN}Allocated Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${DGN}Allocated RAM: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${DGN}Using Bridge: ${BGN}${BRG}${CL}"
  echo -e "${DGN}Using MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${DGN}Using VLAN: ${BGN}Default${CL}"
  echo -e "${DGN}Using Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${BL}Creating an Ubuntu 24.04 VM using the above default settings${CL}"
}

check_root
arch_check
ssh_check
default_settings

msg_info "Escolhendo Storage Location"
STORAGE="local"

msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the Ubuntu 24.04 Disk Image"
URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
wget -q --show-progress $URL
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

msg_info "Creating a Ubuntu 24.04 VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags lacinho-vm -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null

qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=50G \
  -ide2 ${STORAGE}:cloudinit \
  -boot order=scsi0 \
  -serial0 socket \
  -description "Colocar descrição legal depois" >/dev/null

qm resize $VMID scsi0 50G

msg_ok "Created a Ubuntu 24.04 VM ${CL}${BL}(${HN})"
msg_ok "Completed Successfully!\n"
echo -e "Setup Cloud-Init before starting the VM.\n"

# Configurar a VM para usar o Cloud-Init customizado (user-data + network-config)
qm set $VMID --cicustom "user=local:snippets/$CLOUDINIT_YAML_FILE,network=local:snippets/$CLOUDINIT_NET_FILE"

qm start $VMID