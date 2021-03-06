import tasktiger
from redis import Redis 
from rpy2.robjects.packages import importr
from rpy2 import rinterface
import rpy2.robjects as ro
from email.MIMEMultipart import MIMEMultipart
from email.MIMEText import MIMEText
from email.MIMEBase import MIMEBase
import smtplib
from rpy2.robjects import ListVector
import sys # DELETE
import multiprocessing
import rpy2.robjects as robjects
import subprocess

rmarkdown = importr('rmarkdown')

conn = Redis(host="redis")
tiger = tasktiger.TaskTiger(connection=conn)


NECESSARY_FIELDS = ['dataFilePath', 'classFilePath', 'gmtFilePath']
ACCEPTED_FIELDS = ['outFilePath', 'classificationAlgorithm', 'numCrossValidationFolds', 'numRandomIterations',
                   'numCores', 'removePercentLowestExpr', 'removePercentLowestVar'] + NECESSARY_FIELDS
# takes the stuff from the queque
@tiger.task()
def call_gsoa(request):
    local_buffer = []
    def append_output(line):
        print(line)
        local_buffer.append(line)
    # data from task tiger
    print("request: {}".format(request))
    try:
        rmarkdown = importr('rmarkdown')
        args = request.copy()
        for field in NECESSARY_FIELDS:
            args.pop(field)
        if len(str(request.get('dataFilePath'))) < 2:
            return "no data"
        outFilePath = "/data/{}_{}.txt".format(request.get('email', 'results_txt').replace('.com', '').strip(),request.get('dataFilePath').split(".")[0])
        print("email: {}".format(request.get('email', 'results_txt')))
        cmd = ["/gsoa/scripts/run", request.get('dataFilePath', ''),request.get('classFilePath', ''),
               request.get('gmtFilePath', ''), outFilePath, multiprocessing.cpu_count(), "/dev/null",
               request.get('numCrossValidationFolds', ''), "", request.get('numCrossValidationFolds', ''), 
               request.get('classificationAlgorithm', '')]
     
        process = subprocess.Popen(cmd, shell=True,
                           stdout=subprocess.PIPE, 
                           stderr=subprocess.PIPE)
        # wait for the process to terminate
        out, err = process.communicate()
        errcode = process.returncode
        if errcode > 0 : 
           email_error(request.get('email'), "", out+err)

        print("Writing RMarkdown")
        outFilePath_html=outFilePath.replace('txt', 'html')
        rmarkdown.render('/app/GSOA_Report.Rmd', output_file = outFilePath.replace('txt', 'html'),
            params=ListVector({'data1': outFilePath,  'alg': request.get('classificationAlgorithm', 'svm') ,
            'class': request.get('classFilePath', ''), 
            'crossval': request.get('numCrossValidationFolds', ''),
            'data_files' : request.get('dataFilePath', ''),
            'genesets': request.get('gmtFilePath', ''),
            #'hallmarks': 
            'iterations': request.get('numRandomIterations', ''),
            'lowexpress' : request.get('removePercentLowestExpr', ''),
            #'results_hallmark' : 
            'var': request.get('removePercentLowestVar', '')}))  
        email_report(request.get('email'), outFilePath)
    except Exception as e:
        email_error(request.get('email'), e, "")


def email_report(email_address, file_path):
    from_ = 'gsoa.app@gmail.com'
    msgRoot = MIMEMultipart('related')
    msgRoot['Subject'] = 'GSOA Results'
    msgRoot['From'] = from_
    msgRoot['To'] = email_address
    body = "GSOA ran successfully! \n Your raw results are in the '.txt' file. \n The GSOA report is in the 'HTML' file (please downloand HTML file before viewing in web browser) \n Thank you for using GSOA!" 
    msgRoot.attach(MIMEText(body, 'plain'))
    #msg = MIMEMultipart('alternative')
    text = MIMEText('Results File', 'plain')
    #msgRoot.attach(msg)
    with open(file_path) as fp:
        attachment = MIMEBase('text', None)
        attachment.set_payload(fp.read())
        attachment.add_header('Content-Disposition', 'attachment', filename=file_path.split('/')[-1])
    msgRoot.attach(attachment)
    
    with open(file_path.replace('txt', 'html')) as fp:
        attachment1 = MIMEBase('html', None)
        attachment1.set_payload(fp.read())
        attachment1.add_header('Content-Disposition', 'attachment', filename=file_path.split('/')[-1].replace('txt', 'html'))
    msgRoot.attach(attachment1)
    #msg.attach(text)
    mailer = smtplib.SMTP('smtp.gmail.com:587')
    mailer.starttls()
    mailer.login('gsoa.app', 'p@thway@nalysi$')
    mailer.sendmail(from_, email_address, msgRoot.as_string())
    mailer.close()


def email_error(email_address, exception, local_buffer):
    from_ = 'gsoa.app@gmail.com'
    msg = MIMEMultipart()
    msg['From'] = from_
    msg['To'] = email_address
    msg['Subject'] = "GSOA ERROR"
    #msg.preamble = 'GSOA Returned the Following Error:'
    body = "GSOA Returned the Following Error: \n 'Error message: {}: \n {} \n Please email gsoa.app@gmail.com with further questions".format(exception, '\n'.join(local_buffer))
    msg.attach(MIMEText(body, 'plain'))
    #msg.attach(text)
    mailer = smtplib.SMTP('smtp.gmail.com:587')
    mailer.starttls()
    mailer.login('gsoa.app', 'p@thway@nalysi$')
    mailer.sendmail(from_, email_address, msg.as_string())
    mailer.close()
