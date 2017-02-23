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

COPY run_flask.sh /scripts/run_flask.sh
CMD ["/scripts/run_flash.sh"]
    


