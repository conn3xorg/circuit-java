# Local example

Applies circuit-java to a throwaway Rocky Linux 10 container with systemd, installing the OpenJDK 25 JDK from the distribution's packages. You need Conn3x and Podman.

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To look at the result in a login shell, which reads `JAVA_HOME` from `/etc/profile.d`:

```sh
ssh -p 2282 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 'java -version; echo $JAVA_HOME'
```

To install Eclipse Temurin from Adoptium's repository instead, apply with `-var java_source=temurin`. On a host that already has the distribution's OpenJDK, both stay installed, and `java` and `JAVA_HOME` move to Temurin.

`up.sh` listens on `127.0.0.1:2282`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
