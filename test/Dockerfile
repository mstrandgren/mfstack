FROM node

RUN apt-get -o Acquire::Check-Valid-Until=false update -y && apt-get install --no-install-recommends -y -q git ssh

WORKDIR /app

ADD app/ .



EXPOSE 8000

ENTRYPOINT ["./node_modules/coffee-script/bin/coffee", "app.coffee"]