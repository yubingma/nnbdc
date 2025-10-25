mysqldump -h127.0.0.1 -uroot -proot --routines bdc>/var/nnbdc/dbdump/bdc_$(date +%Y%m%d-%H%M%S).sql
