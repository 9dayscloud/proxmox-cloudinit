#!/bin/bash

export VERSION=0.99
export SOURCE_FILE="./source.list"

#Path to your ssh authorized_keys file
#Alternatively, use /etc/pve/priv/authorized_keys if you are already authorized
#on the Proxmox system
export ssh_keyfile=./sshkey/id_ed25519_proxmox.pub
#Username to create on VM template
export ciuser=steve
export cipassword=T2bfjotld

#Name of your storage
export storage=local-zfs

############################################################
# Usage                                                    #
############################################################
#no args:
usage()
{
  # Display Help
  echo "Create Proxmox template using cloud-init image."
  echo
  echo "Usage: $0 [-g|h|l|V] img_name pve_id vm_name"
  echo
  echo "where options include:"
  echo
  echo "  -g     Generate cloud-init image."
  echo "  -h     Print this Help."
  echo "  -l     List available cloud-init image."
  echo "  -v     Print software version and exit."
  echo
}

############################################################
# List                                                     #
############################################################
#no args:
list()
{
  # Show supported cloud-init images
  echo "Supported cloud-init images"
  echo
  cut -d, -f 1 $SOURCE_FILE
}

############################################################
# Create Template                                         #
############################################################
#args:
# vm_id
# vm_name
# file name in the current directory
function create_template() {
    #Print all of the configuration
    echo "Creating template $2 ($1)"

    #Create new VM 
    #Feel free to change any of these to your liking
    qm create $1 --name $2 --ostype l26 
    #Set networking to default bridge
    qm set $1 --net0 virtio,bridge=vmbr0
    #Set display to serial
    qm set $1 --serial0 socket --vga serial0
    #Set memory, cpu, type defaults
    #If you are in a cluster, you might need to change cpu type
    qm set $1 --memory 1024 --cores 2 --cpu host
    #Set boot device to new file
    qm set $1 --scsi0 ${storage}:0,import-from="$(pwd)/$3",discard=on
    #Set scsi hardware as default boot disk using virtio scsi single
    qm set $1 --boot order=scsi0 --scsihw virtio-scsi-single
    #Enable Qemu guest agent in case the guest has it available
    qm set $1 --agent enabled=1,fstrim_cloned_disks=1
    #Add cloud-init device
    qm set $1 --ide2 ${storage}:cloudinit
    # Add tag 
    IFS=- read -r osname verion cloudinit <<< ${2}
    qm set $1 --tags ${osname},${verion},${cloudinit}
    #Set CI ip config
    #IP6 = auto means SLAAC (a reliable default with no bad effects on non-IPv6 networks)
    #IP = DHCP means what it says, so leave that out entirely on non-IPv4 networks to avoid DHCP delays
    qm set $1 --ipconfig0 "ip6=auto,ip=dhcp"
    #Import the ssh keyfile
    qm set $1 --sshkeys ${ssh_keyfile}
    #If you want to do password-based auth instaed
    #Then use this option and comment out the line above
    #qm set $1 --cipassword password
    #Add the user
    qm set $1 --ciuser ${ciuser}
    qm set $1 --cipassword $(openssl passwd -6 ${cipassword})
    #Resize the disk to 10G, a reasonable minimum. You can expand it more later.
    #If the disk is already bigger than 10G, this will fail, and that is okay.
    qm disk resize $1 scsi0 10G
    #Make it a template
    qm template $1

    #Remove file when done
    rm $3
}

############################################################
# generate template using create_template function         #
############################################################
#no args:
function generate()
{
  # Generate proxmox template using create_template function
  echo "Start generate proxmox template ..."
  echo
  img_name=$1
  pve_id=$2
  vm_name=$3
  declare -A imgurl
  while IFS=',' read name url
  do
    imgurl[$name]=$url
    # echo "$name - ${imgurl[$name]}"
  done < $SOURCE_FILE

  for name in "${!imgurl[@]}"
  do
    if [ "$name" == "$img_name" ]
    then
      file=${imgurl[$name]}
      # echo "wget $file"
      # check if file already exists
      if [ -f $file ]; then
        echo "$file already exists. Skip download."
      else 
        wget $file
      fi
      filename=`basename $file`
      # echo "create_template $pve_id $vm_name $filename"
      create_template $pve_id $vm_name $filename
    fi
  done
}

while getopts ":g:hlv" option
do
  case $option in
    h) # display Help
      usage
      exit;;
    \?) # Invalid option
      echo "Error: Invalid option \"-$OPTARG\". Using -h for Help"
      exit;;      
    g) # Generate cloud-init image template
      img=${OPTARG}
      pve_id=$3
      vm_name=$4
      generate $img $pve_id $vm_name
      exit;;
    l) # display available cloud-init images
      list
      exit;;
    v) # display version
      echo "$0 version \"$VERSION\""
      exit;;  
  esac
done

if [ $# -lt 1 ] 
then
    usage
    exit 1
fi

#The images that I've found premade
#Feel free to add your own

### Debian
##Buster (10) (really old at this point)
##wget "https://cloud.debian.org/images/cloud/buster/latest/debian-10-genericcloud-amd64.qcow2"
##create_template 900 "temp-debian-10" "debian-10-genericcloud-amd64.qcow2"
##Bullseye (11) (oldstable)
#wget "https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
#create_template 901 "temp-debian-11" "debian-11-genericcloud-amd64.qcow2" 
##Bookworm (12) (stable)
#wget "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
#create_template 902 "temp-debian-12" "debian-12-genericcloud-amd64.qcow2"
##Trixie (13) (testing) dailies
#wget "https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-genericcloud-amd64-daily.qcow2"
#create_template 903 "temp-debian-13-daily" "debian-13-genericcloud-amd64-daily.qcow2"
##Sid (unstable)
#wget "https://cloud.debian.org/images/cloud/sid/daily/latest/debian-sid-genericcloud-amd64-daily.qcow2"
#create_template 909 "temp-debian-sid" "debian-sid-genericcloud-amd64-daily.qcow2" 
#
### Ubuntu
##20.04 (Focal Fossa) LTS
#wget "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img"
#create_template 910 "temp-ubuntu-20-04" "ubuntu-20.04-server-cloudimg-amd64.img" 
##22.04 (Jammy Jellyfish) LTS
#wget "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
#create_template 911 "temp-ubuntu-22-04" "ubuntu-22.04-server-cloudimg-amd64.img" 
##23.10 (Manic Minotaur)
#wget "https://cloud-images.ubuntu.com/releases/23.10/release/ubuntu-23.10-server-cloudimg-amd64.img"
#create_template 912 "temp-ubuntu-23-10" "ubuntu-23.10-server-cloudimg-amd64.img"
##As 23.10 has *just released*, the next LTS (24.04) is not in dailies yet
#
### Fedora 37
##Image is compressed, so need to uncompress first
#wget https://download.fedoraproject.org/pub/fedora/linux/releases/37/Cloud/x86_64/images/Fedora-Cloud-Base-37-1.7.x86_64.raw.xz
#xz -d -v Fedora-Cloud-Base-37-1.7.x86_64.raw.xz
#create_template 920 "temp-fedora-37" "Fedora-Cloud-Base-37-1.7.x86_64.raw"
### Fedora 38
#wget "https://download.fedoraproject.org/pub/fedora/linux/releases/38/Cloud/x86_64/images/Fedora-Cloud-Base-38-1.6.x86_64.raw.xz"
#xz -d -v Fedora-Cloud-Base-38-1.6.x86_64.raw.xz
#create_template 921 "temp-fedora-38" "Fedora-Cloud-Base-38-1.6.x86_64.raw"
#
### Rocky Linux
##Rocky 8 latest
#wget "http://dl.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud.latest.x86_64.qcow2"
#create_template 930 "temp-rocky-8" "Rocky-8-GenericCloud.latest.x86_64.qcow2"
##Rocky 9 latest
#wget "http://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
#create_template 931 "temp-rocky-9" "Rocky-9-GenericCloud.latest.x86_64.qcow2"

