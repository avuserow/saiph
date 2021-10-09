FROM rakudo-star

RUN exit 1 # TODO: fix integration tests

RUN apt update && apt install -y libreadline-dev gnupg2
RUN echo '\
%echo Generating a basic OpenPGP key\n\
%no-protection\n\
Key-Type: DSA\n\
Key-Length: 1024\n\
Subkey-Type: ELG-E\n\
Subkey-Length: 1024\n\
Name-Real: Joe Tester\n\
Name-Comment: with stupid passphrase\n\
Name-Email: joe@foo.bar\n\
Expire-Date: 0\n\
%commit\n\
%echo done' | gpg2 --batch --generate-key

WORKDIR /root/saiph
RUN git config --global user.name 'Joe Cool'
RUN git config --global user.email 'joe@foo.bar'

ADD META6.json /root/saiph
RUN zef install --deps-only .
ADD . /root/saiph
RUN zef install --/test .
CMD bash
