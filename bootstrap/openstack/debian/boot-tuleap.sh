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

locale-gen en_US
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

apt-get -qy install mysql-server
apt-get -qy install mailman
apt-get -qy install tuleap-all

# Chef install
true && curl -L http://opscode.com/chef/install.sh | bash
