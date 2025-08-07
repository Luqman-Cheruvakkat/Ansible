#!/bin/bash

# Daily Health Check Script for Application
# Author: Generated for application monitoring
# Date: $(date +%Y-%m-%d)

# Configuration - Update these paths and credentials as needed
CATALINA_LOG_PATH="/opt/tomcat/astar_6006_tomcat/logs/catalina.out"
CATALINA_LOG_DIR="/opt/tomcat/astar_6006_tomcat/logs"
REPORT_FILE="/var/log/healthcheck/health-check-$(date +%Y%m%d).log"
EMAIL_RECIPIENT="gokul.as@polussolutions.com"
MYSQL_HOST="192.168.1.225"
MYSQL_PORT="3306"
MYSQL_USER="fibi_dev"
MYSQL_PASSWORD="Polus@#123456"
MYSQL_DATABASE="astar_prod"
ELASTIC_USER=""
ELASTIC_PASS=""
ELASTIC_HOST="http://192.168.1.225:9200"
TOMCAT_SERVICE_NAME="tomcat_astar_6006"

# Thresholds for alerts (customize as needed)
DISK_CRITICAL=90  # Percentage
DISK_WARNING=80   # Percentage
MEM_CRITICAL=90   # Percentage
MEM_WARNING=80    # Percentage
CPU_CRITICAL=90   # Percentage
CPU_WARNING=80    # Percentage

# Error patterns to search for (customize as needed)
ERROR_PATTERNS=(
    "ERROR"
    "Exception"
    "SEVERE"
    "FATAL"
    "OutOfMemoryError"
    "SQLException"
    "ConnectionException"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored headers
print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}=====================================================${NC}"
    echo -e "${BOLD}${CYAN} $1 ${NC}"
    echo -e "${BOLD}${CYAN}=====================================================${NC}"
    echo ""
}

# Function to print sub-headers
print_subheader() {
    echo ""
    echo -e "${BOLD}${BLUE}--- $1 ---${NC}"
    echo ""
}

# Function to log plain messages (no colors or symbols) for reports
log_message() {
    local message="$1"
    local level="$2"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"

    # Plain status tags for report; add [INFO], [ERROR], etc. prefixes if desired
    case "$level" in
        "ERROR")
            echo "${timestamp} ERROR: $message" | tee -a "$REPORT_FILE"
            ;;
        "SUCCESS")
            echo "${timestamp} SUCCESS: $message" | tee -a "$REPORT_FILE"
            ;;
        "WARNING")
            echo "${timestamp} WARNING: $message" | tee -a "$REPORT_FILE"
            ;;
        "ALERT")
            echo "${timestamp} ALERT: $message" | tee -a "$REPORT_FILE"
            ;;
        "INFO")
            echo "${timestamp} INFO: $message" | tee -a "$REPORT_FILE"
            ;;
        *)
            echo "${timestamp} $message" | tee -a "$REPORT_FILE"
            ;;
    esac
}

check_tomcat_service() {
    local service_name="$TOMCAT_SERVICE_NAME"
    local status

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "$service_name"; then
            status="RUNNING"
        else
            if systemctl is-active --quiet tomcat9; then status="RUNNING"
            elif systemctl is-active --quiet tomcat8; then status="RUNNING"
            elif systemctl is-active --quiet tomcat7; then status="RUNNING"
            else status="NOT_RUNNING"
            fi
        fi
    else
        if ps aux | grep -q '[o]rg.apache.catalina.startup.Bootstrap'; then
            status="RUNNING"
        else
            status="NOT_RUNNING"
        fi
    fi

    log_message "Tomcat service status ($service_name): $status" "INFO"
    echo "$status"
}

check_elastic_service() {
    local status
    local response_code
    response_code=$(curl -s -u "$ELASTIC_USER:$ELASTIC_PASS" -o /dev/null -w '%{http_code}' "$ELASTIC_HOST")

    if [[ "$response_code" == "200" ]]; then
        status="AVAILABLE"
    else
        status="UNAVAILABLE"
    fi
    
    log_message "ElasticSearch status: $status (HTTP $response_code)" "INFO"
    echo "$status"
}

check_mysql_service() {
    local status

    if [[ "$MYSQL_HOST" == "localhost" || "$MYSQL_HOST" == "127.0.0.1" ]]; then
        if command -v mysqladmin >/dev/null 2>&1; then
            if mysqladmin -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" ping >/dev/null 2>&1; then
                status="RUNNING"
            else
                status="NOT_RUNNING"
            fi
        else
            if ps aux | grep -q '[m]ysqld'; then
                status="RUNNING"
            else
                status="NOT_RUNNING"
            fi
        fi
    else
        if mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
            status="RUNNING"
        else
            status="NOT_RUNNING"
        fi
    fi

    log_message "MySQL service status (@$MYSQL_HOST:$MYSQL_PORT): $status" "INFO"
    echo "$status"
}

# Function to create HTML email body with simplified system resources
create_html_email() {
    local total_errors="$1"
    local catalina_errors="$2"
    local rotated_errors="$3"
    local mysql_errors="$4"
    local disk_status="$5"
    local memory_status="$6"
    local cpu_status="$7"
    local tomcat_status="$8"
    local elastic_status="$9"
    local mysql_service_status="${10}"
    local server_name=$(hostname)
    local check_date=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { background-color: #d32f2f; color: white; padding: 15px; border-radius: 5px; text-align: center; margin-bottom: 20px; }
        .summary { background-color: #fff3cd; border: 8px solid #ffeaa7; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
        .section { margin-bottom: 20px; border: none solid #ddd; box-shadow: none; border-radius: 5px; overflow: hidden; }
        .section-header { background-color: #6c757d; color: white; padding: 10px; font-weight: bold; border-radius: 5px 5px 0 0; }
        .section-content {  border: none; padding: 15px; background-color: #f8f9fa; border-radius: 0 0 5px 5px; }
        .error-item { background-color: #f8d7da; border: 1px solid #f5c6cb; padding: 10px; margin: 5px 0; border-radius: 3px; }
        .no-errors { color: #28a745; font-weight: bold; }
        .error-count { color: #dc3545; font-weight: bold; font-size: 18px; }
        .info-table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        .info-table td { padding: 8px; border: 1px solid #ddd; }
        .info-table .label { background-color: #e9ecef; font-weight: bold; width: 30%; }
        pre { background-color: #f1f3f4; padding: 10px; border-radius: 3px; font-size: 12px; overflow-x: auto; }
        .status-ok { color: #28a745; }
        .status-warning { color: #ffc107; }
        .status-critical { color: #dc3545; }
        .simple-resources { font-size: 14px; line-height: 1.6; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>🚨 Application Health Check Alert</h2>
            <p>Issues Detected: <span class="error-count">$total_errors</span></p>
        </div>
        
        <div class="summary">
            <h3>📊 Summary Report</h3>
            <table class="info-table">
                <tr><td class="label">Server</td><td>$server_name</td></tr>
                <tr><td class="label">MySQL Host</td><td>$MYSQL_HOST</td></tr>
                <tr><td class="label">Check Date</td><td>$check_date</td></tr>
                <tr><td class="label">Report File</td><td>$REPORT_FILE</td></tr>
            </table>
            
            <h4>Error Breakdown:</h4>
            <ul>
                <li>Current Catalina.out Errors: <span class="error-count">$catalina_errors</span></li>
                <li>Rotated Catalina.out Errors: <span class="error-count">$rotated_errors</span></li>
                <li>MySQL Exception Log Errors: <span class="error-count">$mysql_errors</span></li>
                <li><strong>Total Errors: <span class="error-count">$total_errors</span></strong></li>
            </ul>
        </div>
    
        <div class="section">
            <div class="section-header">🖥️ Service Health</div>
            <div class="section-content" style="border:none; margin-bottom: 20px;">
                <table class="info-table">
                    <tr><td class="label">Tomcat</td><td>$tomcat_status</td></tr>
                    <tr><td class="label">ElasticSearch</td><td>$elastic_status</td></tr>
                    <tr><td class="label">MySQL</td><td>$mysql_service_status</td></tr>
                </table>
            </div>

            <div class="section">
                <div class="section-header">🖥️ System Resources</div>
                <div class="section-content">
                    <div class="simple-resources">
EOF

    # Add simplified system resources - just the key values
    echo "                    <h4>System Status:</h4>"
    echo "                    <ul>"
    
    # Process disk status to show only critical information
    echo "$disk_status" | while read -r line; do
        if [[ -n "$line" ]]; then
            mount_point=$(echo "$line" | awk '{print $1}')
            used=$(echo "$line" | awk '{print $2}')
            total=$(echo "$line" | awk '{print $3}')
            percent=$(echo "$line" | awk '{print $4}')
            status=$(echo "$line" | awk '{print $5}')
            
            status_class="status-ok"
            if [[ "$status" == "CRITICAL" ]]; then
                status_class="status-critical"
            elif [[ "$status" == "WARNING" ]]; then
                status_class="status-warning"
            fi
            
            echo "                        <li>Disk ($mount_point): $percent% used ($used/$total) - <span class=\"$status_class\">$status</span></li>"
        fi
    done
    
    # Process memory status to show only essential info
    echo "$memory_status" | while read -r line; do
        if [[ -n "$line" ]]; then
            type=$(echo "$line" | awk '{print $1}')
            used=$(echo "$line" | awk '{print $2}')
            total=$(echo "$line" | awk '{print $3}')
            percent=$(echo "$line" | awk '{print $4}')
            status=$(echo "$line" | awk '{print $5}')
            
            status_class="status-ok"
            if [[ "$status" == "CRITICAL" ]]; then
                status_class="status-critical"
            elif [[ "$status" == "WARNING" ]]; then
                status_class="status-warning"
            fi
            
            echo "                        <li>$type Memory: $percent% used ($used/$total) - <span class=\"$status_class\">$status</span></li>"
        fi
    done
    
    # Process CPU status
    echo "$cpu_status" | while read -r line; do
        if [[ -n "$line" ]]; then
            percent=$(echo "$line" | awk '{print $1}')
            status=$(echo "$line" | awk '{print $2}')
            
            status_class="status-ok"
            if [[ "$status" == "CRITICAL" ]]; then
                status_class="status-critical"
            elif [[ "$status" == "WARNING" ]]; then
                status_class="status-warning"
            fi
            
            echo "                        <li>CPU Usage: $percent% - <span class=\"$status_class\">$status</span></li>"
        fi
    done

    cat << EOF
                    </ul>
                </div>
            </div>
        </div>
EOF

    # Add Catalina Current Errors Section
    if [[ $catalina_errors -gt 0 ]] && [[ -f "/tmp/catalina_current_$(date +%Y%m%d).tmp" ]]; then
        cat << EOF
        <div class="section">
            <div class="section-header">🔍 Current Catalina.out Errors ($catalina_errors found)</div>
            <div class="section-content">
                <pre>$(cat /tmp/catalina_current_$(date +%Y%m%d).tmp)</pre>
            </div>
        </div>
EOF
    fi

    # Add Catalina Rotated Errors Section
    if [[ $rotated_errors -gt 0 ]] && [[ -f "/tmp/catalina_rotated_$(date +%Y%m%d).tmp" ]]; then
        cat << EOF
        <div class="section">
            <div class="section-header">📁 Rotated Catalina.out Errors ($rotated_errors found)</div>
            <div class="section-content">
                <pre>$(cat /tmp/catalina_rotated_$(date +%Y%m%d).tmp)</pre>
            </div>
        </div>
EOF
    fi

    # Add MySQL Errors Section
    if [[ $mysql_errors -gt 0 ]] && [[ -f "/tmp/mysql_exceptions_$(date +%Y%m%d).tmp" ]]; then
        cat << EOF
        <div class="section">
            <div class="section-header">💾 MySQL Exception Log Errors ($mysql_errors found)</div>
            <div class="section-content">
                <pre>$(cat /tmp/mysql_exceptions_$(date +%Y%m%d).tmp)</pre>
            </div>
        </div>
EOF
    fi

    cat << EOF
        
        <div class="section">
            <div class="section-header">📄 Detailed Report Log</div>
            <div class="section-content">
                <h4>Full Health Check Report:</h4>
                <pre style="max-height: 400px; overflow-y: auto;">$(cat "$REPORT_FILE" 2>/dev/null || echo "Report file not available")</pre>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">📋 Next Steps</div>
            <div class="section-content">
                <ol>
                    <li>Check the detailed report file: <code>$REPORT_FILE</code></li>
                    <li>Review the application logs for root cause analysis</li>
                    <li>Verify database connectivity and performance</li>
                    <li>Monitor system resources (CPU, Memory, Disk)</li>
                    <li>Contact the development team if issues persist</li>
                </ol>
            </div>
        </div>
        
        <div style="text-align: center; margin-top: 20px; color: #6c757d; font-size: 12px;">
            <p>This is an automated health check report generated on $check_date</p>
        </div>
    </div>
</body>
</html>
EOF
}

# Function to send email notification with enhanced formatting
send_notification() {
    local subject="$1"
    local total_errors="$2"
    local catalina_errors="$3"
    local rotated_errors="$4"
    local mysql_errors="$5"
    local disk_status="$6"
    local memory_status="$7"
    local cpu_status="$8"
    local tomcat_status="$9"
    local elastic_status="${10}"
    local mysql_service_status="${11}"

    if command -v mail >/dev/null 2>&1; then
        # Create HTML email content
        local html_content=$(create_html_email "$total_errors" "$catalina_errors" "$rotated_errors" "$mysql_errors" \
            "$disk_status" "$memory_status" "$cpu_status" "$tomcat_status" "$elastic_status" "$mysql_service_status")
        
        # Save HTML content to temporary file
        local temp_html="/tmp/health_check_email_$(date +%Y%m%d_%H%M%S).html"
        echo "$html_content" > "$temp_html"
        
        # Send HTML email
        (
            echo "MIME-Version: 1.0"
            echo "Content-Type: text/html; charset=UTF-8"
            echo "Subject: $subject"
            echo "To: $EMAIL_RECIPIENT"
            echo ""
            cat "$temp_html"
        ) | sendmail "$EMAIL_RECIPIENT"
        
        log_message "HTML email notification sent to $EMAIL_RECIPIENT" "INFO"
        
        # Clean up temporary files
        rm -f "$temp_html"
        rm -f "/tmp/catalina_current_$(date +%Y%m%d).tmp"
        rm -f "/tmp/catalina_rotated_$(date +%Y%m%d).tmp"
        rm -f "/tmp/mysql_exceptions_$(date +%Y%m%d).tmp"
    else
        log_message "mail command not found. Install mailutils for email notifications." "WARNING"
    fi
}

# Function to check current catalina.out for errors
check_current_catalina() {
    print_subheader "Checking Current Catalina.out"
    log_message "Analyzing current catalina.out for error patterns..." "INFO"

    if [[ ! -f "$CATALINA_LOG_PATH" ]]; then
        log_message "catalina.out not found at $CATALINA_LOG_PATH" "ERROR"
        return 1
    fi

    local errors_found=0
    local today=$(date +%Y-%m-%d)
    local error_details=""

    echo -e "  ${BLUE}Scanning for error patterns in today's logs...${NC}"
    
    for pattern in "${ERROR_PATTERNS[@]}"; do
        local count=$(grep "$today" "$CATALINA_LOG_PATH" | grep -c "$pattern")
        if [[ $count -gt 0 ]]; then
            log_message "Found $count occurrences of '$pattern' in today's catalina.out" "ALERT"
            errors_found=$((errors_found + count))
            
            echo -e "    ${YELLOW}→ Capturing last 3 occurrences of '$pattern'...${NC}"
            local pattern_errors=$(grep "$today" "$CATALINA_LOG_PATH" | grep "$pattern" | tail -3)
            error_details+="
=== $pattern ERRORS ($count found) ===
$pattern_errors

"
        else
            echo -e "    ${GREEN}✓ No '$pattern' errors found${NC}"
        fi
    done

    if [[ $errors_found -eq 0 ]]; then
        log_message "No errors found in current catalina.out" "SUCCESS"
    else
        log_message "Total errors found in current catalina.out: $errors_found" "ERROR"
        echo "$error_details" > "/tmp/catalina_current_$(date +%Y%m%d).tmp"
    fi

    echo ""
    return $errors_found
}

# Function to check rotated catalina logs (previous day)
check_rotated_catalina() {
    print_subheader "Checking Rotated Catalina Logs"
    
    local yesterday=$(date -d "yesterday" +%Y-%m-%d)
    local rotated_file="$CATALINA_LOG_DIR/catalina.$yesterday.log"
    local rotated_gz_file="$rotated_file.gz"
    local temp_file=""
    local using_temp=0
    
    log_message "Looking for rotated log files..." "INFO"

    # Check for regular or compressed rotated log
    if [[ -f "$rotated_file" ]]; then
        log_message "Found rotated log file: $rotated_file" "INFO"
        temp_file="$rotated_file"
    elif [[ -f "$rotated_gz_file" ]]; then
        log_message "Found compressed rotated log: $rotated_gz_file" "INFO"
        temp_file="/tmp/catalina_rotated_$(date +%Y%m%d).log"
        gunzip -c "$rotated_gz_file" > "$temp_file"
        using_temp=1
    else
        log_message "No rotated log file found (checked both $rotated_file and $rotated_gz_file)" "WARNING"
        return 0
    fi

    local errors_found=0
    local error_details=""

    echo -e "  ${BLUE}Analyzing rotated log file...${NC}"

    for pattern in "${ERROR_PATTERNS[@]}"; do
        local count=$(grep -c "$pattern" "$temp_file")
        if [[ $count -gt 0 ]]; then
            log_message "Found $count occurrences of '$pattern' in rotated log" "ALERT"
            errors_found=$((errors_found + count))

            echo -e "    ${YELLOW}→ Extracting sample '$pattern' errors...${NC}"
            local pattern_errors=$(grep "$pattern" "$temp_file" | tail -3)
            error_details+="
=== $pattern ERRORS ($count found) ===
$pattern_errors

"
        else
            echo -e "    ${GREEN}✓ No '$pattern' errors found${NC}"
        fi
    done

    if [[ $errors_found -eq 0 ]]; then
        log_message "No errors found in rotated catalina log" "SUCCESS"
    else
        log_message "Total errors found in rotated log: $errors_found" "ERROR"
        echo "$error_details" > "/tmp/catalina_rotated_$(date +%Y%m%d).tmp"
    fi

    # Clean up temporary file if we created one
    [[ $using_temp -eq 1 ]] && rm -f "$temp_file"

    echo ""
    return $errors_found
}

# Function to check MySQL exception.log
check_mysql_exceptions() {
    print_subheader "Checking MySQL Exception Log"
    
    local today=$(date +%Y-%m-%d)
    local mysql_command="SELECT COUNT(*) as error_count FROM exception_log WHERE DATE(CREATE_TIMESTAMP) = '$today';"
    
    log_message "Connecting to MySQL server: $MYSQL_HOST:$MYSQL_PORT" "INFO"

    if command -v mysql >/dev/null 2>&1; then
        echo -e "  ${BLUE}Querying exception_log table for today's entries...${NC}"
        
        local result
        result=$(mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -D"$MYSQL_DATABASE" -se "$mysql_command" 2>/dev/null)

        if [[ $? -eq 0 ]]; then
            if [[ "$result" =~ ^[0-9]+$ ]]; then
                if [[ $result -gt 0 ]]; then
                    log_message "Found $result exception(s) in MySQL exception_log for today" "ALERT"

                    echo -e "    ${YELLOW}→ Fetching detailed exception information...${NC}"
                    
                    local detailed_query="SELECT ERROR_ID, ERROR_CODE, MESSAGE, API_REQUEST, METHOD, DEBUG_MESSAGE, CREATE_TIMESTAMP, CREATE_USER FROM exception_log WHERE DATE(CREATE_TIMESTAMP) = '$today' ORDER BY CREATE_TIMESTAMP DESC LIMIT 5;"

                    local exception_details=""
                    local counter=1
                    
                    while IFS=$'\t' read -r error_id error_code message api_request method debug_message create_timestamp create_user; do
                        echo -e "    ${CYAN}Processing exception #$counter...${NC}"
                        
                        local stacktrace=$(mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -D"$MYSQL_DATABASE" -se "SELECT STACKTRACE FROM exception_log WHERE ERROR_ID = $error_id;" 2>/dev/null | head -3 | tr '\n' ' ')

                        exception_details+="
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXCEPTION #$counter
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERROR_ID        : $error_id
ERROR_CODE      : $error_code
API_REQUEST     : $api_request
METHOD          : $method
MESSAGE         : $message
DEBUG_MESSAGE   : $debug_message
CREATE_TIMESTAMP: $create_timestamp
CREATE_USER     : $create_user
STACKTRACE      : $stacktrace
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"
                        counter=$((counter + 1))
                    done < <(mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -D"$MYSQL_DATABASE" -se "$detailed_query" 2>/dev/null)

                    echo "$exception_details" > "/tmp/mysql_exceptions_$(date +%Y%m%d).tmp"
                    return $result
                else
                    log_message "No exceptions found in MySQL exception_log for today" "SUCCESS"
                    return 0
                fi
            else
                log_message "Unexpected result from MySQL query: $result" "ERROR"
                return 1
            fi
        else
            log_message "Failed to connect to MySQL database at $MYSQL_HOST:$MYSQL_PORT" "ERROR"
            return 1
        fi
    else
        log_message "MySQL client not found. Please install mysql-client package." "ERROR"
        return 1
    fi
}

# Function to check disk space
check_disk_space() {
    df -h | tail -n +2 | while read -r line; do
        # Skip non-physical filesystems
        [[ $line == tmpfs* || $line == udev* || $line == devtmpfs* ]] && continue
        filesystem=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        avail=$(echo "$line" | awk '{print $4}')
        use_percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount=$(echo "$line" | awk '{print $6}')

        status="OK"
        if [[ $use_percent -ge $DISK_CRITICAL ]]; then
            status="CRITICAL"
        elif [[ $use_percent -ge $DISK_WARNING ]]; then
            status="WARNING"
        fi
        echo "$mount $used $size $use_percent $status"
    done
}

# Function to check memory usage
check_memory_usage() {
    local mem_info=$(free -m | awk '/Mem:/ {print $2,$3,$6,$7}')
    local total=$(echo $mem_info | awk '{print $1}')
    local used=$(echo $mem_info | awk '{print $2}')
    local buffers=$(echo $mem_info | awk '{print $3}')
    local cached=$(echo $mem_info | awk '{print $4}')
    local real_used=$((used - buffers - cached))
    local percent=$((100 * real_used / total))

    local ram_status="OK"
    [[ $percent -ge $MEM_CRITICAL ]] && ram_status="CRITICAL"
    [[ $percent -ge $MEM_WARNING && $percent -lt $MEM_CRITICAL ]] && ram_status="WARNING"

    echo "RAM ${real_used}M ${total}M $percent $ram_status"

    local swap_info=$(free -m | awk '/Swap:/ {print $2,$3}')
    local swap_total=$(echo $swap_info | awk '{print $1}')
    local swap_used=$(echo $swap_info | awk '{print $2}')
    local swap_percent=0
    [[ $swap_total -gt 0 ]] && swap_percent=$((100 * swap_used / swap_total))

    local swap_status="OK"
    [[ $swap_percent -ge $MEM_CRITICAL ]] && swap_status="CRITICAL"
    [[ $swap_percent -ge $MEM_WARNING && $swap_percent -lt $MEM_CRITICAL ]] && swap_status="WARNING"

    if [[ $swap_total -gt 0 ]]; then
        echo "Swap ${swap_used}M ${swap_total}M $swap_percent $swap_status"
    else
        echo "Swap NotConfigured 0 0 OK"
    fi
}

# Function to check CPU usage
check_cpu_usage() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    cpu_usage=${cpu_usage%.*}
    local status="OK"
    [[ $cpu_usage -ge $CPU_CRITICAL ]] && status="CRITICAL"
    [[ $cpu_usage -ge $CPU_WARNING && $cpu_usage -lt $CPU_CRITICAL ]] && status="WARNING"
    echo "$cpu_usage $status"
}

# Function to generate summary report
generate_summary() {
    local catalina_errors=$1
    local rotated_errors=$2
    local mysql_errors=$3
    local disk_status=$4
    local memory_info="$5"
    local cpu_status=$6
    local tomcat_status=$7
    local elastic_status=$8
    local mysql_service_status=$9
    local total_errors=$((catalina_errors + rotated_errors + mysql_errors))

    print_header "DAILY HEALTH CHECK SUMMARY"
    echo "Report Details:"
    echo "  Date & Time    : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Server         : $(hostname)"
    echo "  MySQL Host     : $MYSQL_HOST"
    echo "  Report File    : $REPORT_FILE"
    echo ""

    echo "Error Summary:"
    echo "  Current Catalina.out : $catalina_errors errors"
    echo "  Rotated Catalina.out : $rotated_errors errors"
    echo "  MySQL Exception Log  : $mysql_errors errors"
    echo "  Total Errors Found   : $total_errors errors"
    echo ""

    echo "Service Health:"
    printf "  %-15s %-10s\n" "Tomcat" "$tomcat_status"
    printf "  %-15s %-10s\n" "ElasticSearch" "$elastic_status"
    printf "  %-15s %-10s\n" "MySQL" "$mysql_service_status"
    echo ""


    echo "System Resources:"
    echo "  Disk Space:"
    echo "$disk_status" | while read -r line; do
        [[ -n "$line" ]] && echo "    $line"
    done

    echo "  Memory Usage:"
    echo "$memory_info" | while read -r line; do
        [[ -n "$line" ]] && echo "    $line"
    done

    echo "  CPU Usage:"
    echo "$cpu_status" | while read -r line; do
        [[ -n "$line" ]] && echo "    $line"
    done

    echo ""
    if [[ $total_errors -eq 0 && "$tomcat_status" == "TOMCAT RUNNING" && "$elastic_status" == "ELASTIC AVAILABLE" && "$mysql_service_status" == "MYSQL RUNNING" ]]; then
        echo "STATUS: HEALTHY - No issues detected!"
        log_message "Status: HEALTHY - No issues detected" "SUCCESS"
    else
        echo "STATUS: ISSUES DETECTED - Requires immediate attention!"
        log_message "Status: ISSUES DETECTED - Requires attention" "ERROR"
        echo "Sending detailed email notification..."
        send_notification "Application Health Check Alert - $(date +%Y-%m-%d)" \
            "$total_errors" "$catalina_errors" "$rotated_errors" "$mysql_errors" \
            "$disk_status" "$memory_info" "$cpu_status" "$tomcat_status" "$elastic_status" "$mysql_service_status"
    fi
}

main() {
    # Create report directory if it doesn't exist
    mkdir -p "$(dirname "$REPORT_FILE")"
    echo "Daily Health Check Report - $(date '+%Y-%m-%d %H:%M:%S')" > "$REPORT_FILE"
    echo "=========================================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    print_header "DAILY APPLICATION HEALTH CHECK"
    echo "Starting health check at $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Server: $(hostname)"
    echo "MySQL Host: $MYSQL_HOST"
    echo ""

    # Service checks
    local tomcat_status=$(check_tomcat_service)
    local elastic_status=$(check_elastic_service)
    local mysql_service_status=$(check_mysql_service)

    # App checks
    check_current_catalina
    local catalina_errors=$?
    check_rotated_catalina
    local rotated_errors=$?
    check_mysql_exceptions
    local mysql_errors=$?
    local disk_status=$(check_disk_space)
    local memory_info=$(check_memory_usage)
    local cpu_status=$(check_cpu_usage)

    # Summary and notification
    generate_summary "$catalina_errors" "$rotated_errors" "$mysql_errors" "$disk_status" "$memory_info" "$cpu_status" "$tomcat_status" "$elastic_status" "$mysql_service_status"
    print_header "HEALTH CHECK COMPLETED"
    echo "Check completed at $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Report saved to: $REPORT_FILE"
    echo ""
}

main "$@"