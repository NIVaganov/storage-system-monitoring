#!/bin/bash

#
# Это скрипт установщик для системы мониторинга дисковой подсистемы серверов компании FastVPS Eesti OU
# Если у Вас есть вопросы по работе данной системы, рекомендуем обратиться по адресам:
# - https://github.com/FastVPSEestiOu/storage-system-monitoring
# - https://bill2fast.com (через тикет систему)
#

# Данные пакеты обязательны к установке, так как используются скриптом мониторинга
DEBIAN_DEPS="wget libstdc++5 parted smartmontools liblwp-useragent-determined-perl libnet-https-any-perl libcrypt-ssleay-perl libfile-spec-perl"
CENTOS_DEPS="wget libstdc++ parted smartmontools perl-Crypt-SSLeay perl-libwww-perl"

# init.d script для smartd
SMARTD_INIT_DEBIAN=/etc/init.d/smartmontools
SMARTD_INIT_CENTOS=/etc/init.d/smartd

GITHUB_FASTVPS_URL="https://raw.github.com/FastVPSEestiOu/storage-system-monitoring"

# Diag utilities repo
DIAG_UTILITIES_REPO="https://raw.github.com/FastVPSEestiOu/storage-system-monitoring/master/raid_monitoring_tools"

MONITORING_SCRIPT_NAME="storage_system_fastvps_monitoring.pl"

# Monitoring script URL
MONITORING_SCRIPT_URL="$GITHUB_FASTVPS_URL/master/$MONITORING_SCRIPT_NAME"

# Monitoring CRON file
CRON_FILE=/etc/cron.hourly/storage-system-monitoring-fastvps

# Installation path
INSTALL_TO=/usr/local/bin

# smartd config command to run repiodic tests (short/long)
SMARTD_COMMAND="# smartd.conf by FastVPS
\n# backup version of distrib file saved to /etc/smartd.conf.dist
\n
\n# Discover disks and run short tests every day at 02:00 and long tests every sunday at 03:00
\nDEVICESCAN -d removable -n standby -s (S/../.././02|L/../../7/03)"

ARCH=
DISTRIB=

#
# Functions
#

check_n_install_debian_deps()
{
    echo "Installing Debian dependencies..."
    
    apt-get update >/dev/null
    res=`apt-get install -y $DEBIAN_DEPS`
    if [ $? -ne 0 ]
    then
        echo "Something went wrong while installing dependencies. APT log:"
        echo $res
    fi
    echo "Finished installation of debian dependencies."
}

check_n_install_centos_deps()
{
    echo "Installing CentOS dependencies..."
    res=`yum install -y $CENTOS_DEPS`
    if [ $? -ne 0 ]
    then
        echo "Something went wrong while installing dependencies. YUM log:"
        echo $res
    fi
    echo "Finished installation of CentOS dependencies."  
}

# Проверяем наличие аппаратный RAID контроллеров и в случае наличия устанавливаем ПО для их мониторинга
check_n_install_diag_tools()
{
    # utilities have suffix of ARCH, i.e. arcconf32 or megacli64
    ADAPTEC_UTILITY=arcconf
    LSI_UTILITY=megacli

    lsi_raid=0
    adaptec_raid=0

    parted_diag=`parted -mls`

    echo "Checking hardware for LSI or Adaptec RAID controllers..."
    if [ -n "`echo $parted_diag | grep -i adaptec`" ]
    then
        echo "Found Adaptec raid"
        adaptec_raid=1
    fi
    if [ -n "`echo $parted_diag | grep -i lsi`" ]
    then
        echo "Found LSI raid"
        lsi_raid=1
    fi

    if [ $adaptec_raid -eq 0 -a $lsi_raid -eq 0 ]
    then
        echo "Hardware raid not found"
        return
    fi

    echo ""

    if [ $adaptec_raid -eq 1 ]
    then
        echo "Installing diag utilities for Adaptec raid..."
        wget --no-check-certificate "$DIAG_UTILITIES_REPO/arcconf$ARCH" -O"$INSTALL_TO/$ADAPTEC_UTILITY"
        chmod +x "$INSTALL_TO/$ADAPTEC_UTILITY" 
        echo "Finished installation of diag utilities for Apactec raid"
    fi

    echo ""

    if [ $lsi_raid -eq 1 ]
    then
        echo "Installing diag utilities for LSI MegaRaid..."

        # Dependencies installation
        case $DISTRIB in
            debian)
                wget --no-check-certificate "$DIAG_UTILITIES_REPO/megacli.deb" -O/tmp/megacli.deb
                dpkg -i /tmp/megacli.deb
                rm -f /tmp/megacli.deb
            ;;  
            centos)
                yum install -y "$DIAG_UTILITIES_REPO/megacli.rpm"
            ;;  
            *)  
                echo "Can't install LSI tools for you distributive"
                exit 1
            ;;  
        esac

        echo "Finished installation of diag utilities for Apactec raid"
    fi
}

install_monitoring_script()
{
    echo "Installing monitoring.pl into $INSTALL_TO..."
    wget --no-check-certificate $MONITORING_SCRIPT_URL -O"$INSTALL_TO/$MONITORING_SCRIPT_NAME"
    chmod +x "$INSTALL_TO/$MONITORING_SCRIPT_NAME"

    echo "Installing CRON task to $CRON_FILE"
    echo "#!/bin/bash" > $CRON_FILE
    echo "perl $INSTALL_TO/$MONITORING_SCRIPT_NAME --cron" >> $CRON_FILE
    chmod +x $CRON_FILE
}


start_smartd_tests()
{
    echo -n "Creating config for smartd... "

    # Backup /etc/smartd.conf
    if [ ! -e /etc/smartd.conf.dist ]
    then
        mv /etc/smartd.conf /etc/smartd.conf.dist
    fi

    echo -e $SMARTD_COMMAND > /etc/smartd.conf
    echo "done."

    # restart service
    case $DISTRIB in
        debian)
        $SMARTD_INIT_DEBIAN restart
        ;;

        centos)
        $SMARTD_INIT_CENTOS restart
        ;;
    esac

    if [ $? -ne 0 ]
    then
        echo "smartd failed to start. This may be caused by absence of disks SMART able to monitor."
        tail /var/log/daemon.log
    fi
}

#
# Start installation procedure
#

if [ -n "`echo \`uname -a\` | grep -e \"-686\|i686\"`" ]
then
    ARCH=32
fi
if [ -n "`echo \`uname -a\` | grep -e \"amd64\|x86_64\"`" ]
then
    ARCH=64
fi

if [ -n "`cat /etc/issue | grep -i \"Debian\"`" ]
then
    DISTRIB=debian
fi

if [ -n "`cat /etc/issue | grep -i \"CentOS\"`" ]
then
    DISTRIB=centos
fi

if [ -n "`cat /etc/issue | grep -i \"Parallels\"`" ]
then
    DISTRIB=centos
fi

echo "We working on $DISTRIB $ARCH"

# Dependencies installation
case $DISTRIB in
    debian)
    check_n_install_debian_deps
    ;;

    centos)
    check_n_install_centos_deps
    ;;

    *)
    echo "Can't determine OS. Exiting..."
    exit 1
    ;;
esac

# Diagnostic tools installation
check_n_install_diag_tools

# Monitoring script installation
install_monitoring_script

# Periodic smartd tests
start_smartd_tests

echo "Please call command $MONITORING_SCRIPT_NAME and check it output manually"
echo "Checking disk system...";
$INSTALL_TO/$MONITORING_SCRIPT_NAME --detect


