# INSTALL DEPENDENCIES (based on DEBIAN/UBUNTU packages names)

## OS-LEVEL DEPENDENCES

Install packages:

    apt-get install libprotobuf-dev libprotoc-dev g++ libstdc++6 libstdc++-8-dev # (or more newer libstdc++-<NUMBER>-dev)

Add path to `cc1` to env var `$PATH`:

    export PATH=$PATH:$(dirname $(${CCPREFIX}gcc -print-prog-name=cc1))

Add symbolic link from `libstdc++.so.6` to `libstdc++.so`:

    ln -s /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib/x86_64-linux-gnu/libstdc++.so

Install package for spell check:

    apt-get install spell

## INSTALL CPAN MODULES

    cpanm --installdeps --with-develop .        # module dependencies
    dzil authordeps --missing | cpanm           # to install dzil dependencies

# SETUP

    dzil setup

# RUN TESTS

    prove -l t
    dzil test

# BUILD

    dzil build

# RELEASE/UPLOAD TO CPAN

    # write changes to "Changes" file
    # update version in Avatica::Client::VERSION
    dzil release
