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
    libxml2-dev \
    python \
    python-pip
RUN    R -e "install.packages(c('mlr', 'DT', 'doParallel', 'foreach', 'annotate', 'XML'), repos='https://cran.rstudio.com/')"
RUN R -e "source('https://bioconductor.org/biocLite.R');biocLite('limma'); biocLite('GSEABase'); biocLite('edgeR')"

RUN R -e "source('https://bioconductor.org/biocLite.R');biocLite('GSEABase')"
RUN wget https://bitbucket.org/srp33/gsoa/downloads/GSOA_0.99.9.tar.gz \
   && R CMD INSTALL GSOA_0.99.9.tar.gz

RUN pip install rpy2==2.4.2 flask Flask-API markdown

RUN R -e "install.packages(c('e1071', 'ROCR', 'rmarkdown','googleVis'), repos='https://cran.rstudio.com/')"

# installing the queue and the queue database
RUN apt-get install -y python-psutil parallel git
RUN pip install tasktiger redis supervisor numpy scipy sklearn psutil 
RUN R -e "install.packages(c('shiny', 'rmarkdown', 'flexdashboard'), repos='https://cran.rstudio.com/')"
RUN wget https://github.com/closeio/tasktiger/archive/master.zip && \
    unzip master.zip && \
    cd tasktiger-master && \
    python setup.py install && \
    cp -r tasktiger/lua /usr/local/lib/python2.7/dist-packages/tasktiger/
RUN git clone https://srp33@bitbucket.org/srp33/gsoa.git
COPY run_flask.sh /scripts/run_flask.sh
RUN chmod +x /scripts/run_flask.sh
COPY supervisord.conf /etc/supervisord.conf
RUN mkdir -p /var/log/supervisord
# opens the port
EXPOSE 5000

# main docker script 
CMD ["/scripts/run_flask.sh"]
    


