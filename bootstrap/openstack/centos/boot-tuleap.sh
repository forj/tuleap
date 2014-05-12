#!/bin/bash

function GetJson
{
 python -c "exec(\"import json\\njson_d=open('$1').read()\\ndata=json.loads(json_d)\\nprint(data['$2'])\")"
}

# make sure that the passed in gitlink is a valid git repository url
function GitLinkCheck
{
   _LINK=$1
   if [ "$_LINK" = "" ] || [ "$_LINK" = "default" ] ; then
     # this is a default git url, return non-zero so the caller knows.
     return 2
   fi
   # validate we got a valid git URL
   _LINK_PROTOCOL=$(echo $_LINK | awk -F'://' '{printf $1}')
   if   [ "$_LINK_PROTOCOL" = "ssh" ]   ||
        [ "$_LINK_PROTOCOL" = "http" ]  ||
        [ "$_LINK_PROTOCOL" = "https" ] ||
        [ "$_LINK_PROTOCOL" = "git" ]   ||
        [ "$_LINK_PROTOCOL" = "file" ]  ||
        [ "$_LINK_PROTOCOL" = "SSH" ]   ||
        [ "$_LINK_PROTOCOL" = "HTTP" ]  ||
        [ "$_LINK_PROTOCOL" = "HTTPS" ] ||
        [ "$_LINK_PROTOCOL" = "GIT" ]   ||
        [ "$_LINK_PROTOCOL" = "FILE" ]  ; then
        return 0
    else
        echo "ERROR: $_LINK does not have a valid protocol for git"
        return 1 
    fi
}

echo "################# BOOT-Ero Start step 1 #################"

set -x

#locale-gen en_US
# TODO: find if we can source meta.js values from facter since we
#  have all meta.js in facters now.
if [ -f /config/meta.js ]
then
   PREFIX=/config
fi

if [ ! -f $PREFIX/meta.js ]
then
   echo "Boot image invalid. Cannot go on!"
   exit 1
fi


. /etc/environment
_PROXY="$(GetJson $PREFIX/meta.js webproxy)"

# Chef install
true && curl -L http://opscode.com/chef/install.sh | bash

yum -qy install git 
mkdir -p /opt/tuleap-workspace/
cd /opt/tuleap-workspace
git clone https://github.com/Enalean/tuleap-vagrant.git
cd tuleap-vagrant/
git submodule init
git submodule update

chef-solo -j solo/rpm.json -c solo/solo.rb

PUBLIC_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)

sed -e "s/tuleap.local/$PUBLIC_IP/g" /etc/tuleap/conf/local.inc --in-place


#rpm -i http://ftp.nluug.nl/pub/os/Linux/distr/fedora-epel/6/x86_64/epel-release-6-8.noarch.rpm
#rpm -i http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el6.rf.x86_64.rpm
#rpm --import http://apt.sw.be/RPM-GPG-KEY.dag.txt
#yum-config-manager --enable rpmforge
#yum-config-manager --enable rpmforge-extras
#sed -e "s|http://mirrorlist.repoforge.org/el6/mirrors-rpmforge-extras|http://mirrorlist.repoforge.org/el6/mirrors-rpmforge-extras\nincludepkgs = git\* perl-Git\*|" /etc/yum.repos.d/rpmforge.repo --in-place
#
#
#yum-config-manager --add-repo=http://ci.tuleap.net/yum/tuleap/rhel/6/dev/x86_64/
#
#yum -qy install perl-IO-Compress
#yum -qy install --enablerepo=rpmforge-extras tuleap-all



