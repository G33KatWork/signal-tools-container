FROM phusion/baseimage:0.9.19
LABEL maintainer "bibor@bastelsuse.org"
LABEL version="0.2.0"

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

ENV JFLAG=-j4
USER root
RUN apt-get update && apt-get upgrade -yf && apt-get clean && apt-get autoremove
RUN apt-get install -y sudo git subversion wget zip unzip cmake build-essential #for building gnuradio
RUN export DEBIAN_FRONTEND=noninteractive && \
	apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
	vim apt-utils wireshark  wireshark python-scipy gqrx-sdr software-properties-common xterm #common tools


##### gnuradio install script
RUN export PKGLIST="libqwt6 libfontconfig1-dev libxrender-dev libpulse-dev swig g++	automake autoconf libtool python-dev libfftw3-dev libcppunit-dev libboost-all-dev libusb-dev libusb-1.0-0-dev fort77 libsdl1.2-dev python-wxgtk2.8 git-core	libqt4-dev python-numpy ccache python-opengl libgsl0-dev python-cheetah python-mako python-lxml doxygen qt4-default qt4-dev-tools libusb-1.0-0-dev libqwt5-qt4-dev libqwtplot3d-qt4-dev pyqt4-dev-tools python-qwt5-qt4 cmake git-core wget libxi-dev python-docutils gtk2-engines-pixbuf r-base-dev python-tk liborc-0.4-0 liborc-0.4-dev libasound2-dev python-gtk2 libzmq libzmq-dev libzmq1 libzmq1-dev python-requests python-sphinx comedi-dev python-zmq libncurses5 libncurses5-dev" && \
	export CMAKE_FLAG1=-DPythonLibs_FIND_VERSION:STRING="2.7" && \
	export CMAKE_FLAG2=-DPythonInterp_FIND_VERSION:STRING="2.7"

RUN  for pkg in $PKGLIST; do checkpkg; done && \
	for pkg in $PKGLIST; do sudo apt-get -y --ignore-missing install $pkg; done


#### add "signals" user #####
# alternate user config
# ADD user.cfg /tmp/user.cfg
#RUN useradd -m signals && echo "$(cat /tmp/user.cfg | head -n 1 | tr -d '\n'):$(cat /tmp/user.cfg | tail -n 1 | tr -d '\n')" | chpasswd && adduser "$(cat /tmp/user.cfg | head -n 1 | tr -d '\n')" sudo &&\
#	usermod -a -G video signals
# RUN rm /tmp/user.cfg
RUN useradd -m signals && echo "signals:signals" | chpasswd && adduser signals sudo &&\
	usermod -a -G video signals && \
  chsh -s /bin/bash signals

#x2goserver
USER root
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-add-repository ppa:x2go/stable && \
    apt-get update && \
    apt-get install -y x2goserver x2goserver-xsession

# enable ssh & regenerate kesy
USER root
RUN echo "PasswordAuthentication no" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
RUN rm -f /etc/service/sshd/down
RUN /etc/my_init.d/00_regen_ssh_host_keys.sh

#add configs
USER  signals
WORKDIR /home/signals/
RUN mkdir .ssh
COPY configs/ssh/* ./.ssh/
COPY configs/home/* ./
USER root
RUN chown -R signals /home/signals


##### git #####
USER signals
RUN mkdir -p /home/signals/src/gnuradio
WORKDIR /home/signals/src/gnuradio
RUN export v=Master/HEAD &&\
	export PULLED_LIST="gnuradio uhd rtl-sdr gr-osmosdr gr-iqbal hackrf gr-baz bladeRF libairspy"

RUN git clone --progress --recursive http://git.gnuradio.org/git/gnuradio.git
WORKDIR /home/signals/src/gnuradio/gnuradio
RUN git checkout maint
WORKDIR /home/signals/src/gnuradio
RUN git clone --progress  https://github.com/EttusResearch/uhd && \
	git clone --progress git://git.osmocom.org/rtl-sdr && \
	git clone --progress git://git.osmocom.org/gr-osmosdr  && \
	git clone --progress git://git.osmocom.org/gr-iqbal.git && \
	git clone https://github.com/Nuand/bladeRF.git
WORKDIR /home/signals/src/gnuradio/gr-iqbal
RUN git submodule init && \
	git submodule update
WORKDIR /home/signals/src/gnuradio
RUN git clone --progress https://github.com/mossmann/hackrf.git && \
	mkdir airspy && \
	cd  airspy && \
	git clone https://github.com/airspy/host

#### uhd build ####
WORKDIR /home/signals/src/gnuradio/uhd
RUN git checkout && mkdir -p ./host/build
WORKDIR /home/signals/src/gnuradio/uhd/host/build

##DEBUG
USER root
RUN apt-get install python-pip libboost-all-dev --yes
USER signals
RUN pip install mako
##END DEBUG
RUN cmake $CMAKE_FLAG1 $CMAKE_FLAG2 $CMF1 $CMF2  $UCFLAGS ../ && \
	make clean && \
	make $JFLAG
USER root
RUN sudo rm -f /usr/local/lib*/libuhd* && \
	sudo make $JFLAG install && \
	sudo ldconfig


#### rtl build ####

##DEBUG
USER root
RUN apt-get install libusb-1.0-0-dev --yes
##END DEBUG

### rtl-sdr ###
USER signals
WORKDIR /home/signals/src/gnuradio/rtl-sdr
RUN cmake $CMAKE_FLAG1 $CMAKE_FLAG2 $CMF1 $CMF2 . && \ 
	make clean && \
	make $JFLAG
USER root
RUN sudo make install

### hackrf ###

##DEBUG
USER root
RUN apt-get install pkg-config --yes
##END DEBUG

USER signals
WORKDIR /home/signals/src/gnuradio/hackrf
RUN cmake $CMAKE_FLAG1 $CMAKE_FLAG2 $CMF1 $CMF2 -DINSTALL_UDEV_RULES=ON host/ && \
		make clean && \
		make $JFLAG
USER root
RUN make install

### gr-iqbal ###
USER signals
RUN mkdir -p /home/signals/src/gnuradio/gr-iqbal/build
WORKDIR /home/signals/src/gnuradio/gr-iqbal/build

RUN	cmake .. $CMAKE_FLAG1 $CMAKE_FLAG2 $CMF1 $CMF2 && \
		make clean && \
		make $JFLAG
USER root
RUN sudo make install

### bladeRF ###
USER signals
WORKDIR /home/signals/src/gnuradio/bladeRF/host
RUN	cmake . $CMAKE_FLAG1 $CMAKE_FLAG2 $CMF1 $CMF2 && \
		make clean && \ 
		make $JFLAG
USER root
RUN sudo make install

### airspy ###
USER signals
RUN mkdir -p  /home/signals/src/gnuradio/airspy/host/build
WORKDIR /home/signals/src/gnuradio/airspy/host/build
RUN	cmake .. $CMAKE_FLAG1 $CMAKE_FLAG2 $CMF1 $CMF2 && \
		make clean && \
		make $JFLAG
USER root
RUN sudo make install

### gr-osmosdr ###
WORKDIR /home/signals/src/gnuradio/gr-osmosdr
RUN	cmake . $CMAKE_FLAG1 $CMAKE_FLAG2 $CMF1 $CMF2 && \
		make clean && \
		make $JFLAG
USER root
RUN sudo make install && \
	sudo ldconfig


#### gnuradio build
USER signals
WORKDIR /home/signals/src/gnuradio/gnuradio
RUN git checkout
USER root
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && \
	echo "/usr/local/lib64" >> /etc/ld.so.conf.d/local.conf && \
	sudo ldconfig
USER signals
ENV PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig

RUN mkdir build
WORKDIR /home/signals/src/gnuradio/gnuradio/build
RUN cmake -DENABLE_BAD_BOOST=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo $CMAKE_FLAG1 $CMAKE_FLAG2 $CMF1 $CMF2 $GCFLAGS ../ && \
	make $JFLAG clean &&\
	make $JFLAG
USER root
RUN sudo rm -rf /usr/local/include/gnuradio/ && \
	sudo rm -f /usr/local/lib*/libgnuradio* && \
	sudo make $JFLAG install && \
	sudo ldconfig

#### firmware ####
USER root
RUN uhd_images_downloader

#### groups ####
USER root
RUN /usr/sbin/usermod -a -G usrp signals

#### udev ####
USER root
RUN	cp /home/signals/src/gnuradio/uhd/host/utils/uhd-usrp.rules /etc/udev/rules.d/10-usrp.rules && \
	chown root /etc/udev/rules.d/10-usrp.rules && \
	chgrp root /etc/udev/rules.d/10-usrp.rules && \
	cp /home/signals/src/gnuradio/rtl-sdr/rtl-sdr.rules /etc/udev/rules.d/15-rtl-sdr.rules && \
	chown root /etc/udev/rules.d/15-rtl-sdr.rules && \
	chgrp root /etc/udev/rules.d/15-rtl-sdr.rules

#### sysctl ####
USER root
RUN echo "net.core.rmem_max = 1000000" >> /etc/sysctl.conf && \
	echo "net.core.wmem_max = 1000000" >> /etc/sysctl.conf && \
	echo "kernel.shmmax = 2147483648" >> /etc/sysctl.conf && \
	echo "@usrp  - rtprio 50" >> /etc/security/limits.conf

RUN echo "export PYTHONPATH=/usr/local/lib/python2.7/dist-packages" >> ~/.bashrc


##### build gr-baz #####
WORKDIR /home/signals/src
RUN git clone https://github.com/bibor/gr-baz.git && mkdir -p ./gr-baz/build
WORKDIR /home/signals/src/gr-baz/build
RUN cmake .. && make
USER root
RUN sudo make install && sudo ldconfig

USER root
RUN chown -R signals /home/signals
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
