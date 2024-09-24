folder=~/.ssh

if [ ! -d "$folder" ]; then
    echo "mkdir $folder"
    mkdir $folder
    chmod 700 $folder
fi

file=~/.ssh/authorized_keys

if [ ! -f "$file" ]; then
    echo "touch $file"
    touch $file
    chmod 600 $file
fi

pubKey="AAAAB3NzaC1yc2EAAAADAQABAAABgQC5XzoBJjMZZ+qWEcOj3RKphgGIFXTsA9pSxY0igvh2ZYVb/Z3yHfGUXZtXBuXZz1lim0nOL1B7rDdag60rfy/5umvPdSXX7ttlhmVwr6L00A98aXHBOu2cBQ26UyfD1DQ1PQFDfae9c22zhm+ZlhIU0rtNoWycAtRa54QWm+s93eeDxfssFipckFKlHpr7l6ckJZPp6Q+OYekvB3JtiXzToqdEKDzZMW+xCS8+RvcWkuja4yt3+jUsz8C9Y9MPQrbBJBnI2aDMpnrS2Y2HrlpCXDlcTHFFVpvRvk8P4lZ0U2rC9igRgY6E0Sx0SdaFVV7p9Jjj439oixQeSP0j8Y3dxMNkA5t4hubQ2GanKV3z2LtfuYlnf8dfBMw9s6jToQKA/wW8gS0IVCsQWrfBIsR7zjj1WLdhbLmPWFucnaz6f3e/JUTnbuYBsB/gBtGcgl2bvmx5Si0Np3aAEt4ZjJKhqigituZxX600Galy4H004/vWUIa6OuM+0US+0MMFBak="


if grep -q "$pubKey" $file; then
    echo "pubKey already in $file"
else
    echo "add pubKey to $file"
    echo $pubKey >> $file
fi
