#!/bin/bash

function Help
{
 echo "Usage is $0 [--proxy <ProxySetting>] [--gitlink <GitLink>] [--gitbranch <branch name>] [--kit <prefix>] [--apt-mirror <MirrorUrl>]
NOTE   : A required fog config file written in YAML format is generated (~/.cache/forj/openstack.fog) from your keystone resource information (OS_USERNAME,OS_TENANT_NAME,OS_PASSWORD,OS_AUTH_URL,OS_REGION_NAME).
WARNING: Currently, this bootstraps scripts only support openstack fog files."
}

# Environment definition and defaults

PROTO_IMG="CentOS 6.3 Server 64-bit 20130116"
MI_NAME=standard.small
NODE_IMAGE=standard.xsmall


if [ $# -eq 0 ]
then
   Help
   exit 1
fi

GITLINK=https://github.com/Enalean/tuleap.git

while [ $# -ne 0 ]
do
  OPT=False
   case "p$1" in
     "p--proxy")
       PROXY_FLAG="--meta webproxy=$2"
       echo "Use proxy=$2"
       OPT=True
       shift;shift;;
     "p--apt-mirror")
       APTMIRROR="$2"
       echo "Use apt-mirror=$2"
       OPT=True
       shift;shift;;
     "p--gitbranch")
       GITBRANCH="$2"
       echo "Use gitbranch=$2"
       OPT=True
       shift;shift;;
     "p--gitlink")
       GITLINK="$2"
       echo "Use gitlink=$2"
       OPT=True
       shift;shift;;
     "p--kit")
       CDK_PREFIX="$2"
       echo "Use Kit name=$2"
       OPT=True
       shift;shift;;
   esac
   if [ "$OPT" = False ]
   then
      echo "ERROR: Option $1 not recognized."
      Help
      exit 1
   fi
done

if [ "$CDK_PREFIX" = "" ]
then
   CDK_PREFIX=ds
fi

if [ "$OS_AUTH_URL" = "" ] || [ "$OS_TENANT_NAME" = "" ] || [ "$OS_USERNAME" = "" ] || [ "$OS_PASSWORD" = "" ]
then
   echo "OS_AUTH_URL, OS_TENANT_NAME, OS_USERNAME, OS_PASSWORD required.

If you built from a devstack, you will need to load with 'source ~/devstack/openrc admin admin'
If you built from fedora packstack, you will need to source ~/keystonerc_admin"
  exit 1
fi
mkdir -p ~/.cache/forj
FOG_FILE=~/.cache/forj/openstack.fog

if [ ! -f ~/.ssh/nova-USWest-AZ3.pub ]
then
   echo "~/.ssh/nova-USWest-AZ3.pub was not found on your local ssh environment.
Please get the nova USWest AZ3 public key from HPCLOUD container and save it in .ssh. Then retry."
   exit 1
fi

if [ ! -f ~/.ssh/vagrant_az3.pub ]
then
   echo "~/.ssh/vagrant_az3.pub was not found on your local ssh environment.
Please get the nova USWest AZ3 public key from HPCLOUD container and save it in .ssh. Then retry."
   exit 1
fi

# pre-configure .fog file to suit the target environment. Extract the region from the auth URL
# Region might have to be updated if the default region (availability-zone) is not appropriate
OS_A_U="$(echo $OS_AUTH_URL | awk '{gsub(/\/$/,""); print}')"
if [[  "$(echo $OS_AUTH_URL | grep hpcloud)" ]]
then
 OS_R_N="openstack_region: $(echo $OS_AUTH_URL | grep hpcloud  | awk  -F"//" '{print $2}'| awk -F'.' '{print $1"."$2}')"
# enable floating IP's
 FLOATING_IP=true
fi

FLOATING_IP=true
echo "default:
 openstack_api_key: $OS_PASSWORD
 openstack_auth_url: $OS_A_U/tokens
 openstack_tenant: $OS_TENANT_NAME
 openstack_username: $OS_USERNAME
 $OS_R_N
forj:
 provider: openstack
" > $FOG_FILE

if [ ! -r "$FOG_FILE" ]
then
   echo "'$FOG_FILE' is unreadable. Exiting."
   exit 1
fi

GITLINK_FLAG="--meta gitlink=$GITLINK"
if [ "$GITBRANCH" != "" ]
then
   GITBRANCH_FLAG="--meta gitbranch=$GITBRANCH"
fi
if [ "$APTMIRROR" != "" ]
then
   APTMIRROR_FLAG="--meta apt-mirror=$APTMIRROR"
fi


# Keep track of the bootstrap/devstack directory
TOP_DIR=$(cd $(dirname "$0") && pwd)

# Import common functions
source $TOP_DIR/functions
set -x


# Checking that nova and glance client tool are already installed locally.
if [ -z "$(which glance)" ] || [ -z "$(which nova)"  ]
then
   echo "glance and/or nova are not installed. i
On fedora, use the following:
sudo yum install /usr/bin/glance /usr/bin/nova
On ubuntu, use the following: (not tested)
sudo apt-get install /usr/bin/glance /usr/bin/nova"
   exit 1
fi

# Verify that all expected flavors exist

# Create xsmall flavor if not present
FLAVOR=$(nova flavor-list | grep $MI_NAME | get_field 1)
if [[ "$FLAVOR" = "" ]]; then
    FLAVOR=$(nova flavor-create $MI_NAME 6 2048 20 1| grep $MI_NAME | get_field 1)
fi

N_FLAVOR=$(nova flavor-list | grep $NODE_IMAGE | get_field 1)
if [[ "$N_FLAVOR" = "" ]]; then
    N_FLAVOR=$(nova flavor-create $NODE_IMAGE 7 1024 20 1| grep $MI_NAME | get_field 1)
fi


SECGROUP="default"
# Configure Security Group Rules
# nova secgroup-add-rule default tcp 1 29418 0.0.0.0/0
# nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
if ! nova secgroup-list-rules $SECGROUP | grep -q icmp; then
    nova secgroup-add-rule $SECGROUP icmp -1 -1 0.0.0.0/0
fi
if ! nova secgroup-list-rules $SECGROUP | grep -q " tcp .* 22 "; then
    nova secgroup-add-rule $SECGROUP tcp 22 22 0.0.0.0/0
fi
#TODO ADD individual ports here, remove the global open
if ! nova secgroup-list-rules $SECGROUP | grep -q " tcp .* 65535 "; then
    nova secgroup-add-rule default tcp 1 65535 0.0.0.0/0
fi

# configure keypairs.
# it is assumed that private and public keys are available in the ~/.ssh directory
#
# nova keypair-add --pub-key nova-USWest-AZ3.pub nova
# nova keypair-add --pub-key vagrant_az3.pub vagrant_az3
if ! nova keypair-list | grep -q nova; then
    nova keypair-add --pub-key ~/.ssh/nova-USWest-AZ3.pub nova
fi
if ! nova keypair-list | grep -q vagrant_az3; then
    nova keypair-add --pub-key ~/.ssh/vagrant_az3.pub vagrant_az3
fi

# nova boot --flavor FLAVOR_ID --image IMAGE_ID --key_name KEY_NAME \
#  --user-data mydata.file --security_group SEC_GROUP NAME_FOR_INSTANCE \
#  --meta KEY=VALUE --meta KEY=VALUE
#
# nova flavor-list
#+----+-----------+-----------+------+-----------+------+-------+-------------+-----------+
#| ID | Name      | Memory_MB | Disk | Ephemeral | Swap | VCPUs | RXTX_Factor | Is_Public |
#+----+-----------+-----------+------+-----------+------+-------+-------------+-----------+
#| 1  | m1.tiny   | 512       | 1    | 0         |      | 1     | 1.0         | True      |
#| 2  | m1.small  | 2048      | 20   | 0         |      | 1     | 1.0         | True      |
#| 3  | m1.medium | 4096      | 40   | 0         |      | 2     | 1.0         | True      |
#| 4  | m1.large  | 8192      | 80   | 0         |      | 4     | 1.0         | True      |
#| 42 | m1.nano   | 64        | 0    | 0         |      | 1     | 1.0         | True      |
#| 5  | m1.xlarge | 16384     | 160  | 0         |      | 8     | 1.0         | True      |
#| 84 | m1.micro  | 128       | 0    | 0         |      | 1     | 1.0         | True      |
#+----+-----------+-----------+------+-----------+------+-------+-------------+-----------+
#
#nova image-list
#+--------------------------------------+------------------------------------------+--------+--------+
#| ID                                   | Name                                     | Status | Server |
#+--------------------------------------+------------------------------------------+--------+--------+
#| 15e6e4a7-8e17-4a41-bfe3-81805766a841 | F17-i386-cfntools                        | ACTIVE |        |
#| b5f1eb5b-150f-4244-a0f2-8fa2108c6e13 | F17-x86_64-cfntools                      | ACTIVE |        |
#| b3c6007c-de5d-4280-88f3-347e03b04be9 | F18-i386-cfntools                        | ACTIVE |        |
#| 5eeb655f-c3c9-4c62-9628-ab707a4f8754 | F18-x86_64-cfntools                      | ACTIVE |        |
#| a995f0e2-27ea-414b-b12c-1ef027f68af4 | F19-i386-cfntools                        | ACTIVE |        |
#| 5080ddf3-846c-4a57-8b1f-595b96ac2b8f | F19-x86_64-cfntools                      | ACTIVE |        |
#| 3ebe3b0d-ff02-41d8-8ef3-e856a1927efd | ubuntu-12.04-server-cloudimg-amd64-disk1 | ACTIVE |        |
#| 33d92294-f39a-4c33-9012-bee06a915d84 | ubuntu-13.04-server-cloudimg-amd64-disk1 | ACTIVE |        |
#| c085ca89-283c-49dc-a400-04f5c9c4d331 | ubuntu-13.10-server-cloudimg-amd64-disk1 | ACTIVE |        |
#+--------------------------------------+------------------------------------------+--------+--------+

IMAGE=$(nova image-list | grep "$PROTO_IMG" | get_field 1)

if [[ "$IMAGE" = "" ]]
then
   IMG=~/.cache/forj/precise-server-cloudimg-amd64-disk1.img

   if [ ! -r $IMG ]
   then
      pushd ~/.cache/forj/
      wget http://uec-images.ubuntu.com/precise/current/precise-server-cloudimg-amd64-disk1.img
      popd
   fi
IMAGE=$(glance image-create --name "Ubuntu Precise 12.04 LTS Server 64-bit 20121026 (b)" \
 --is-public=Yes --container-format=bare --disk-format=qcow2 --file $IMG | grep id | get_field 2)

fi

P_IMAGE=$(nova image-list | grep "$PROTO_IMG" | get_field 1)

if [[ "$P_IMAGE" = "" ]]
then
   IMG=~/.cache/forj/precise-server-cloudimg-amd64-disk1.img

   if [ ! -r $IMG ]
   then
      pushd ~/.cache/forj/
      wget http://uec-images.ubuntu.com/precise/current/precise-server-cloudimg-amd64-disk1.img
      popd
   fi
   glance image-create --name "$PROTO_IMG" --is-public=Yes --container-format=bare --disk-format=qcow2 --file $IMG

fi


VM_NAME=tuleap.$CDK_PREFIX

mkdir -p .build
#cp bootstrap.sh cloud-config-tuleap.yaml .build/
cp bootstrap.sh .build/bootstrap.sh
cp boot-tuleap.sh .build/boot-tuleap.sh
cp cloud-config-tuleap.yaml .build/cloud-config-tuleap.yaml

CLOUD_CONFIG=/opt/config/fog

echo "
mkdir -p ${CLOUD_CONFIG}; echo \"$(cat $FOG_FILE)\" > ${CLOUD_CONFIG}/cloud.fog" >> .build/bootstrap.sh



#echo "echo '$(cat $FOG_FILE | base64 -w0 )' | base64 -d  > /opt/config/fog/cloud.fog" >> .build/bootstrap.sh

if [ "$APTMIRROR" != "" ]
then
    # As soon as we are using a local mirror, ask cloud-init to not update the sources.list anymore.
#    echo "apt_mirror: $APTMIRROR" >> .build/cloud-config-tuleap.yaml
     echo "apt_preserve_sources_list: true" >> .build/cloud-config-tuleap.yaml
fi
echo "output: {all: '| tee -a /var/log/cloud-init.log'}" >> .build/cloud-config-tuleap.yaml

./write-mime-multipart.py .build/bootstrap.sh:text/cloud-boothook .build/cloud-config-tuleap.yaml .build/boot-tuleap.sh -o mime.txt
#./write-mime-multipart.py .build/bootstrap.sh:text/cloud-boothook  .build/boot-tuleap.sh -o mime.txt

#./write-mime-multipart.py .build/bootstrap.sh:text/cloud-boothook  -o mime.txt

dos2unix -q mime.txt

# private subnet management
NETS=$(nova net-list)
if [[ -z "$NETS" ]]
then
#nova net-list empty, use neutron to get results
 NET_NUMS=$(neutron net-list | grep '[0-9a-z][0-9a-z]*-' |sed 's/ *| */|/g' | awk -F'|' '{ print $2 }' | wc -l)
 if [ "$NET_NUMS" -gt 1 ]
 then
	NETUUID="$(neutron net-list | grep 'tuleap' | head -n1 | get_field 1)"
	NETUUID_OPT="--nic net-id=$NETUUID"
	NETUUID_META="--meta netuuid=$NETUUID"
 fi
else
	#nova net commands to manage networking
	NET_NUMS=$(nova net-list | grep '[0-9a-z][0-9a-z]*-' |sed 's/ *| */|/g' | awk -F'|' '{ print $2 }' | wc -l)
 if [ "$NET_NUMS" -gt 1 ]
 then
    NETUUID="$(nova net-list | grep 'tuleap' | head -n1 | get_field 1)"
    NETUUID_OPT="--nic net-id=$NETUUID"
	NETUUID_META="--meta netuuid=$NETUUID --meta network_name=tuleap"
 fi
fi
echo $NETUUID


#NET_NUMS=$(nova net-list | grep '[0-9a-z][0-9a-z]*-' |sed 's/ *| */|/g' | awk -F'|' '{ print $2 }' | wc -l)
#if [ "$NET_NUMS" -gt 1 ]
#then
#   NETUUID="--nic net-id=$(nova net-list | grep '[0-9a-z][0-9a-z]*-' |sed 's/ *| */|/g' | awk -F'|' '$3 ~ /private/ {print $2 }')"
#fi

#HPCloud does not use config-drive correctly, disable option
if [[ ! "$(echo $OS_AUTH_URL | grep hpcloud )" ]]
then
	CONFIG_DRIVE="--config-drive y"
fi

VM_UUID=$(nova boot --image $IMAGE --flavor $FLAVOR \
 --key_name nova --user-data mime.txt \
--meta erosite=tuleap.$CDK_PREFIX \
--meta erodomain=forj.io \
--meta eroip=127.0.0.1 \
--meta cdkdomain=$CDK_PREFIX.forj.io \
--meta cdksite=tuleap \
--meta tenantid=$CDK_PREFIX \
 $PROXY_FLAG $GITLINK_FLAG $GITBRANCH_FLAG $APTMIRROR_FLAG $NETUUID_META\
 $CONFIG_DRIVE \
 $NETUUID_OPT $VM_NAME \
| grep ' id ' | get_field 2)
die_if_not_set $LINENO VM_UUID "Failure launching $VM_NAME"

ACTIVE_TIMEOUT=60
rm mime.txt
rm .build/*
# Check that the status is active within ACTIVE_TIMEOUT seconds
if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova show $VM_UUID | grep status | grep -q ACTIVE; do sleep 1; done"; then
    echo "server didn't become active!"
    exit 1
fi

sleep 2
if [[ "$FLOATING_IP" = "true" ]]
then
# find free or create floating IP address
 FLOATING_IP=$(nova floating-ip-list | grep " - " | get_field 1 | head -n1)
 if [[ -z "$FLOATING_IP" ]]
 then
 FLOATING_IP=$(nova floating-ip-create | grep [0-9]. | get_field 1)
 fi
 nova floating-ip-associate $VM_UUID $FLOATING_IP
fi
# Get the instance local IP
IP=$(nova list --name $VM_NAME --fields networks | grep '10.' |get_field 2 | awk -F '=' '{print $2}' | awk -F',' '{print $1}')

die_if_not_set $LINENO IP "Failure retrieving IP address"

# Removing IP ssh host in known_hosts.
ssh-keygen -R $IP
ssh-keygen -R $FLOATING_IP

if [[ ! "$(echo $OS_AUTH_URL | grep hpcloud )" ]]
then
 ACTIVE_TIMEOUT=60
 # Private IPs can be pinged in single node deployments
 ping_check "$PRIVATE_NETWORK_NAME" $IP $ACTIVE_TIMEOUT
fi

nova show tuleap.$CDK_PREFIX

