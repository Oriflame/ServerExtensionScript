if (!(test-path C:\logs)) {mkdir C:\logs }
echo started > C:\logs\log.txt
netsh advfirewall firewall set rule group=”File and Printer Sharing” new enable=Yes 