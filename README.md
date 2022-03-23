## Description
This is a BASH script to create and get a ZeroSSL server certificate via REST API. It is used to set up a script that performs domain validation via email.

## What it does
After creating a CSR file, this script requests certificate creation via the REST API. Specify domain validation by email. The domain verification is then performed based on the received email. After successful domain verification, it gets the generated server certificate.

## Running the installer
```
sudo useradd -s /sbin/nologin certbot
sudo sh -c "echo 'default_privs = certbot' >> /etc/postfix/main.cf
sudo sh -c "echo 'certbot:        |\"/usr/bin/bash /home/certbot/verify_domains.sh\"' >> /etc/aliases
sudo newaliases
sudo git clone https://github.com/3kami3/zerossl-gencert-viamail.git /home/certbot
sudo vi /home/certbot/.env
sudo chown -R certbot:certbot /home/certbot
sudo bash /home/certbot/zerossl-gencert.sh
```
