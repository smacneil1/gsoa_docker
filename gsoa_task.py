import tasktiger
from redis import Redis 
from rpy2.robjects.packages import importr
import rpy2.robjects as ro

gsoa = importr('GSOA')

conn = Redis(host="redis")
tiger = tasktiger.TaskTiger(connection=conn)


NECESSARY_FIELDS = ['dataFilePath', 'classFilePath', 'gmtFilePath']
ACCEPTED_FIELDS = ['outFilePath', 'classificationAlgorithm', 'numCrossValidationFolds', 'numRandomIterations',
                   'numCores', 'removePercentLowestExpr', 'removePercentLowestVar'] + NECESSARY_FIELDS

@tiger.task()
def call_gsoa(request):
    print("request: {}".format(request))
    gsoa = importr('GSOA')
    conn = Redis(host="redis")
    tiger = tasktiger.TaskTiger(connection=conn)
    args = request.copy()
    for field in NECESSARY_FIELDS:
        args.pop(field)
    if len(str(request.get('dataFilePath'))) < 2:
        return "no data"
    print("email: {}".format(request.get('email', 'results_txt')))       
    result =  gsoa.GSOA_ProcessFiles(dataFilePath=request.get('dataFilePath', ''),
                                     classFilePath=request.get('classFilePath', ''),
                                     gmtFilePath=request.get('gmtFilePath', ''),
                                     outFilePath="/data/{}".format(request.get('email', 'results_txt')))