#!/usr/bin/bash

# Tor Crawler v0.1
# https://github.com/alex2ndg

# This is an small script that will go through a list of v3 Onion Links and crawl' them 
# to search for specific string(s). Output results will be saved on a csv result file.
# Of course, for using this you should be connected to the Tor network. To be used under *nix.
# Package pre-requisites: tor, curl, wget.
# Sudo permissions required for systemctl and tor service & files.

# 1. Tor Network - Onion availability tests.
## Is Tor installed? If so, let's start it.
tor --version && echo "Tor Installed" || (e=$?; echo "Tor Not Installed. Please install and retry"; (exit $c))
sudo systemctl start tor
## Which Tor IP are we using?
torsocks wget -qO - https://api.ipify.org; echo " << You are using this Tor IP"
## Tor runs by default on port 9050. Are we all clear then?
curl --socks5 localhost:9050 --socks5-hostname localhost:9050 -s https://check.torproject.org/ | cat | grep -m 1 Congratulations | xargs
ss -nlt |grep 9050 && echo "TCP 9050 Configured" || (e=$?; echo "TCP 9050 not accesible. Please review and restart"; (exit $c))
## Now, let's make this a Tor Shell.
source torsocks on

# 2. Tor Control Port
## Let's generate a 25-char random string with OWASP logic
rand=$(tr -dc 'A-Za-z0-9!"#$%&'\''()*+,-./:;<=>?@[\]^_`{|}~' </dev/urandom | head -c 25  ; echo)
## Now let's hash this random string as a password for the tor port
torpwd=$(tor --hash-password "$rand")
## And let's define this torpwd hashed for the control port
printf "HashedControlPassword $torpwd\nControlPort 9051\n" | sudo tee -a /etc/tor/torrc
## Let's restart tor
sudo systemctl restart tor
## Now TCP 9051 should be up;
ss -nlt |grep 9051 && echo "TCP 9051 Configured" || (e=$?; echo "TCP 9051 not accesible. Please review and restart"; (exit $c))

# 3. Let's prepare the terrain
## Just for the sake of it, let's change the circuit;
source torsocks off
echo -e "AUTHENTICATE $rand\r\nsignal NEWNYM\r\nQUIT" | nc 127.0.0.1 9051
torsocks wget -qO - https://api.ipify.org; echo " << You are using this Tor IP"
source torsocks on

# 4. Now let's start crawling.
## You'll need an urls.txt file with the v3 onion URLs to crawl
for url in `cat urls.txt`; do
    domain=$(echo $url |awk -F '//' '{print $2}')
    echo "Processing $domain now..."
    echo "Please have in mind that it might take some time to complete."
    wget -q --show-progress --recursive --html-extension --convert-links --domains $domain $url
    # This will go through all of the webpage retrieving only html files inside of the domain.
    echo "$domain crawl completed."
done

# 5. Now, for each of the downloaded webpages, let's search for the desired strings
## You'll need an strings.txt file with the desired strings to look for.
timestamp=$(date +%Y%m%d%H%m%S)
mkdir results_$timestamp
for dir in `find . -name *.onion`; do
    odir=$(echo $dir |awk -F '/' '{print $2}')
    mkdir results_$timestamp/$odir
    cd $dir
    for string in `cat ../strings.txt`; do
        echo "Looking for $string on $odir files..."
        # This will search case-insensitive and recursive with full links for each string.
        grep -iFR $string * >> ../results_$timestamp/results_$odir.txt
    done
    cat ../results_$timestamp/results_$odir.txt |awk -F ':' '{print $1}' |sort |uniq > ../results_$timestamp/files_$odir.txt
    for file in `cat ../results_$timestamp/files_$odir.txt`; do
        echo "Copying HTML results to the result dir..."    
        cp $file ../results_$timestamp/$odir/
    done
    # If you want to save the downloaded files to check later with wget -N and retrieve the new options, comment the following line.
    cd .. && rm -rf $dir
done

# 6. Final cleanup
## Let's close the shell Tor connection
source torsocks off
sudo systemctl stop tor
## And remove the last two lines from torrc to avoid issues when restarting
sudo sed -i -n -e :a -e '1,2!{P;N;D;};N;ba' /etc/tor/torrc
## ... as well as the latest parameters
unset rand torpwd timestamp

exit $? 
