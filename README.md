# dartfrog
DataDog integration for Swarm cluster

## Generate private ssh key for deployments

This is described at [Setting An SSH Private Key with Codeship](https://documentation.codeship.com/pro/builds-and-configuration/setting-ssh-private-key/).

    docker run -it --rm -v $(pwd):/keys/ codeship/ssh-helper generate "denis@sfrdc.com" && \
      docker run -it --rm -v $(pwd):/keys/ codeship/ssh-helper prepare && \
      rm codeship_deploy_key && \
      npm run env:encrypt:codeship

