# Audit DB, Log and Container Log
#LOGPATH="/opt/cyberark/dap/logs" # FOR CUSTOMERS
CONTAINERENGINE=podman
CONTAINERSNAME=$($CONTAINERENGINE ps --format "{{.Names}}")
AUDITLOG_NAME="audit.log"
CONTAINERLOG_NAME="container-log.json"
MaxMessages=10000
MaxSize=500 # in MB (NO DECIMAL) for Audit and Container Log - NEW

# Compress File
date_string=$(date +"%Y%m%d")
date_string_logrotate=$(date '+%Y-%m-%d')
date_string_log=$(date +"%Y%m")

# Log Audit File Script
LOG_DIR="/var/log"
BASE_FILENAME="log-rotator"
LOG_FILE="$LOG_DIR/$date_string_log-$BASE_FILENAME.log"

# Log Storage Path
LOGSTORAGE_DIR="/opt/cyberark/dap/logs/conjur-log"

for container in $CONTAINERSNAME; do

    LOGPATH="/opt/cyberark/dap/logs"  #FOR LOCAL ONLY
    echo $container
    #set -x
    # ===============================================================================
    # Check if the file exists
    # ===============================================================================
    if [ ! -f "$LOG_FILE" ]; then
        # Create a new log file if it doesn't exist
        touch "$LOG_FILE"
    fi

    if [ ! -d "$LOGSTORAGE_DIR" ]; then
        # Create a new log dir if it doesn't exist
        mkdir -p "$LOGSTORAGE_DIR"
    fi
    # ===============================================================================
    # Check Size Messages Audit DB
    # ===============================================================================

    ## Get count messages
    countMessages=$($CONTAINERENGINE exec -u conjur $container psql -d audit -p 5433 -c "select count(*) from messages;" | sed -n '3p')

    echo "$date_string_logrotate:$countMessages Audit Messages" >> $LOG_FILE

    if [ $countMessages -gt $MaxMessages ]; then
        $CONTAINERENGINE exec -u postgres $container psql -p 5433 -d audit -c 'truncate messages';

        echo "$date_string_logrotate: Truncate DB" >> $LOG_FILE
    fi

    # ===============================================================================
    # Check Audit Log +  Compress
    # ===============================================================================
    auditLogSize=$(du -m "$LOGPATH/$AUDITLOG_NAME" | awk '{print $1}')
    cd "$LOGPATH"

    echo "$date_string_logrotate: audit log size $auditLogSize MB" >> $LOG_FILE
    if [ $auditLogSize -gt $MaxSize ]; then
        tar -czf "$LOGPATH/$date_string-audit.tar.gz" "$AUDITLOG_NAME"
        mv "$LOGPATH/$date_string-audit.tar.gz" "$LOGSTORAGE_DIR/$date_string-audit.tar.gz"
        $CONTAINERENGINE exec $container truncate -s0 "/var/log/conjur/$AUDITLOG_NAME"
        # :> "$LOGPATH/$AUDITLOG_NAME"
        #$CONTAINERENGINE exec $container rm -rf "/var/log/conjur/$AUDITLOG_NAME"
        #$CONTAINERENGINE exec $container touch /var/log/conjur/audit.log
	    #$CONTAINERENGINE exec $container syslog-ng-ctl reload > /dev/null
        echo "$date_string_logrotate: Compressing audit message" >> $LOG_FILE
    fi

    # Move all file .tar.gz that compressed by Conjur Logrotate.d - NEW
    mv "$LOGPATH"/*.gz "$LOGSTORAGE_DIR"

    #set +x

    # ===============================================================================
    # Check Container Log +  Compress - NEW
    # ===============================================================================
    
    echo "$date_string_logrotate: container log size $auditLogSize MB" >> $LOG_FILE
    containerLogSize=$(du -m "$LOGPATH/$CONTAINERLOG_NAME" | awk '{print $1}')

    if [ $containerLogSize -gt $MaxSize ]; then
        tar -czf "$LOGPATH/$date_string-containerlog.tar.gz" "$CONTAINERLOG_NAME"
        mv "$LOGPATH/$date_string-containerlog.tar.gz" "$LOGSTORAGE_DIR/$date_string-containerlog.tar.gz"
        rm -rf "$LOGPATH/$CONTAINERLOG_NAME"
        echo "$date_string_logrotate: Compressing container log message" >> $LOG_FILE
    fi

done

