FROM r-base:latest

MAINTAINER Winston Chang "winston@rstudio.com"

RUN apt-get update && apt-get install -y -t unstable \
    sudo \
    gdebi-core \
    pandoc \
    pandoc-citeproc \
    libcurl4-gnutls-dev \
    libcairo2-dev/unstable \
    libxt-dev \
    r-cran-xml \
    libxml2-dev

RUN    R -e "install.packages(c('mlr', 'doParallel', 'foreach', 'annotate', 'XML'), repos='https://cran.rstudio.com/')"
RUN R -e "source('https://bioconductor.org/biocLite.R');biocLite('limma'); biocLite('GSEABase'); biocLite('edgeR')"

RUN R -e "source('https://bioconductor.org/biocLite.R');biocLite('GSEABase')"
RUN wget https://bitbucket.org/srp33/gsoa/downloads/GSOA_0.99.9.tar.gz \
   && R CMD INSTALL GSOA_0.99.9.tar.gz

RUN apt-get install -y python python-pip
RUN pip install rpy2 flask Flask-API markdown
COPY run_flask.sh /scripts/run_flask.sh
RUN chmod +x /scripts/run_flask.sh
RUN R -e "install.packages(c('e1071', 'ROCR'), repos='https://cran.rstudio.com/')"

# installing the queue and the queue database
RUN pip install tasktiger redis supervisor
COPY supervisord.conf /etc/supervisord.conf
RUN mkdir -p /var/log/supervisord
# opens the port
EXPOSE 5000

# main docker script 
CMD ["/scripts/run_flask.sh"]
    


