FROM python:3.12.3

WORKDIR /app
RUN git clone https://github.com/vladmandic/automatic .

CMD ["/app/webui.sh", "--debug"]
