FROM ubuntu:focal
# set as env, we are noninteractive in the container too
ENV DEBIAN_FRONTEND=noninteractive
# for tzdata, otherwise there will be a prompt
RUN echo "Europe/Zurich" > /etc/timezone

ENV SNAPCRAFT_SETUP_CORE=1

ARG CLANG_VERSION
RUN echo "building image for clange version ${CLANG_VERSION}"

ARG deps='apt-transport-https ca-certificates software-properties-common curl gpg-agent gnupg' 
ARG soft="python3 python3-pip cmake make clang-${CLANG_VERSION} libomp-${CLANG_VERSION}-dev llvm-${CLANG_VERSION} llvm-${CLANG_VERSION}-dev\
  clang++-${CLANG_VERSION} texinfo build-essential fakeroot devscripts automake autotools-dev \
  wget snapd git ruby-full sudo python2 python3-setuptools unzip"
RUN echo ${CLANG_VERSION}
RUN apt-get clean
RUN apt-get update 
RUN apt-get install -y ${deps} --no-install-recommends --force-yes
RUN curl https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
RUN add-apt-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal main"
RUN add-apt-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-9 main"
RUN add-apt-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-10 main"
RUN add-apt-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-11 main"
RUN add-apt-repository universe
# add the cmake repo
RUN curl https://apt.kitware.com/keys/kitware-archive-latest.asc | apt-key add -
RUN apt-add-repository 'deb https://apt.kitware.com/ubuntu/ focal main'
RUN apt-get update
RUN apt-get install -y ${soft} --no-install-recommends --force-yes
RUN apt-get purge -y --auto-remove ${DEPS}
RUN ln -s /usr/bin/clang-${CLANG_VERSION} /usr/bin/clang
RUN ln -s /usr/bin/clang++-${CLANG_VERSION} /usr/bin/clang++
# install needed python modules
RUN python3 -m pip install pyyaml

# install pyenv (needed for travis...)
RUN curl https://pyenv.run | bash
RUN curl https://bootstrap.pypa.io/2.7/get-pip.py --output get-pip.py
RUN python2 get-pip.py
RUN python2 -m pip install --upgrade pip
# so travis can use sudo
RUN useradd -m docker && echo "docker:docker" | chpasswd && adduser docker sudo

ENV HOME_DIR /home/fba_code/
ENV SRC_DIR ${HOME_DIR}/code
ENV BUILD_DIR ${HOME_DIR}/build
ENV BITCODES_DIR ${HOME_DIR}/bitcodes

# set the environment variables for c/cxx
# ENV CC ${HOME_DIR}/wrappers/clang
# ENV CXX ${HOME_DIR}/wrappers/clang++

# fixes for qmake
# https://salsa.debian.org/lucas/collab-qa-tools/-/blob/master/modes/clang10
# Force the configruation of qmake to workaround this issue:
# https://clang.debian.net/status.php?version=9.0.1&key=FAILED_PARSE_DEFAULT

RUN apt install --yes --no-install-recommends --force-yes qt5-qmake
RUN cp /usr/lib/x86_64-linux-gnu/qt5/mkspecs/linux-clang/* /usr/lib/x86_64-linux-gnu/qt5/mkspecs/linux-g++/
RUN ls -al /usr/lib/x86_64-linux-gnu/qt5/mkspecs/linux-g++/
RUN cat /usr/lib/x86_64-linux-gnu/qt5/mkspecs/linux-g++/qmake.conf
ENV QMAKESPEC=/usr/lib/x86_64-linux-gnu/qt5/mkspecs/linux-clang/

RUN sed -i -e "s|compare_problem(2,|compare_problem(0,|g" /usr/bin/dpkg-gensymbols
RUN sed -i -e "s|compare_problem(1,|compare_problem(0,|g" /usr/bin/dpkg-gensymbols
RUN grep "compare_problem(" /usr/bin/dpkg-gensymbols

RUN apt search '^gcc-[0-9]*[.]*[0-9]*$' | grep -o '\bgcc[a-zA-Z0-9:_.-]*' |\
  xargs -I {} echo "{}" hold | dpkg --set-selections


RUN mkdir -p ${HOME_DIR}
WORKDIR ${HOME_DIR}
ADD docker/init.py init.py
ADD code_builder/utils/ utils
ADD code_builder/build_systems/ build_systems
ADD code_builder/wrappers/ wrappers
ADD code_builder/ci_systems/ ci_systems


# fake travis commands so scripts don't fail
RUN ln -s "${HOME_DIR}/wrappers/travis_retry.sh" /usr/bin/travis_retry
RUN ln -s "${HOME_DIR}/wrappers/travis_cmd.sh" /usr/bin/travis_cmd
RUN ln -s "${HOME_DIR}/wrappers/exit0.sh" /usr/bin/travis_time_start
RUN ln -s "${HOME_DIR}/wrappers/exit0.sh" /usr/bin/travis_time_finish
RUN ln -s "${HOME_DIR}/wrappers/exit0.sh" /usr/bin/travis_terminate
RUN ln -s "${HOME_DIR}/wrappers/pass_cmd.sh" /usr/bin/travis_wait
RUN ln -s "${HOME_DIR}/wrappers/exit0.sh" /usr/bin/travis_assert

# https://clang.debian.net/
# https://github.com/sylvestre/debian-clang/blob/master/clang-setup.sh
# force, since apt installed compilers

RUN ln -fs ${HOME_DIR}/wrappers/clang /usr/bin/cc\
  && ln -fs ${HOME_DIR}/wrappers/clang++ /usr/bin/c++\
  && ln -fs ${HOME_DIR}/wrappers/clang++ /usr/bin/cpp\
  && ln -fs ${HOME_DIR}/wrappers/clang /usr/bin/gcc\
  && ln -fs ${HOME_DIR}/wrappers/clang++ /usr/bin/g++

# replace all version of gcc
RUN cd ${HOME_DIR}/wrappers && ./replace_compilers.sh 4.6 4.7 4.8 4.9 5 6 7 8 9 10



# Check if gcc, g++ & cpp are actually clang
RUN gcc --version|grep clang > /dev/null || exit 1
RUN g++ --version|grep clang > /dev/null || exit 1
RUN cpp --version|grep clang > /dev/null || exit 1

ENTRYPOINT ["python3", "-u", "init.py", "input.json"]
