#!/bin/bash
#
# 2023/10/19 add new user to multiple sftp servers
#
####################################################################################################
sftp_servers=( 'https://sftp.server.one' 'https://sftp.server.two' 'https://sftp.server.three' )
admin_un=
admin_pw=

url_login='api/v2/token'
url_logout='api/v2/logout'
url_create_user='api/v2/users'

####################################################################################################
help() {
    cat >&2 <<EOF
Connect to multiple sftp servers, creating a new user on each one

Successful output should look like this:
    Creating user 'new_user_123'
    201 :: sftp.server.one
    201 :: sftp.server.two
    201 :: sftp.server.three

Usage: ./add_user.sh [-h] [-e email] [-p password] [-r role] -s ssh_key -u username

-h              Display help
-e email        New user's email address (optional)
-p password     New user's password. Default value is 'changeme'
-r role         New user's role (optional)
-s ssh_key      New user's public ssh key
-u username     New user's username
EOF
}

####################################################################################################
while getopts ":e:hp:r:s:u:" opt; do
    case "$opt" in
        e)  email="$OPTARG" ;;
        p)  password="$OPTARG" ;;
        r)  role="$OPTARG" ;;
        s)  ssh_key="$OPTARG" ;;
                u)  username="$OPTARG" ;;
        h)  help
            exit 0
            ;;
        *)  echo "Invalid option: -$OPTARG" >&2
            help
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

####################################################################################################
#build JSON body
if [[ -n "$role" ]]; then
    body=$(jq -n \
        --arg un "$username" --arg email "${email:-}"  --arg pw "${password:-changeme}"  --arg ssh "$ssh_key" --arg role "$role" \
        '{status: 1, username: $un, email: $email, password: $pw, public_keys: [ $ssh ], has_password: true, role: $role, permissions: {"/": [ "list", "download"]}}')

else
    body=$(jq -n \
        --arg un "$username" --arg email "${email:-}"  --arg pw "${password:-changeme}"  --arg ssh "$ssh_key" \
        '{status: 1, username: $un, email: $email, password: $pw, public_keys: [ $ssh ], has_password: true, permissions: {"/": [ "list", "download"]}}')
fi

#prompt for admin credentials if necessary
if [[ -z "$admin_un" ]]; then
    read -p "admin username: " admin_un
    if [[ -z "$admin_un" ]]; then
        echo "no admin user provided" >&2
        exit
    fi
fi
if [[ -z "$admin_pw" ]]; then
    read -s -p "admin password: " admin_pw
    echo
    if [[ -z "$admin_pw" ]]; then
        echo "no admin password provided" >&2
                exit
    fi
fi
if [[ -z "$admin_otp" ]]; then
    read -s -p "admin OTP (optional): " admin_otp
    echo
fi

echo "Creating user '$username'"
for host in "${sftp_servers[@]}"; do
    #login
    if [[ -n "$admin_otp" ]]; then
        token="Authorization: bearer $(curl -s -u "$admin_un:$admin_pw" -H "X-SFTPGO-OTP: $admin_otp" "$host/$url_login" | jq -r .access_token)"
    else
        token="Authorization: bearer $(curl -s -u "$admin_un:$admin_pw" "$host/$url_login" | jq -r .access_token)"
    fi

    #create user
    response_code=$(curl -s -o /dev/null -w "%{http_code}" -H "$token" -X POST -d @- "$host/$url_create_user" <<< "$body")
    echo "$response_code :: ${host#*://}"

    #logout
    curl -s -H "$token" "$host/$url_logout" > /dev/null
done
