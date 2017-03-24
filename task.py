import tasktiger
from redis import Redis 
from rpy2.robjects.packages import importr
import rpy2.robjects as ro

gsoa = importr('GSOA')

conn = Redis(host="redis://redis")
tiger = tasktiger.TaskTiger(connection=conn)


NECESSARY_FIELDS = ['dataFilePath', 'classFilePath', 'gmtFilePath', 'outFilePath']
ACCEPTED_FIELDS = ['classificationAlgorithm', 'numCrossValidationFolds', 'numRandomIterations',
                   'numCores', 'removePercentLowestExpr', 'removePercentLowestVar'] + NECESSARY_FIELDS

@tiger.task()
def call_gsoa(request):
    gsoa = importr('GSOA')
    conn = Redis(host="redis://redis")
    tiger = tasktiger.TaskTiger(connection=conn)
    args = request.data.copy()
    for field in NECESSARY_FIELDS:
        args.pop(field)
    if len(str(request.data.get('dataFilePath'))) < 2:
        return "no data"
    print("result: {}".format(request.data))
    print("email: {}".format(request.data.get('email', 'results_txt')))       
    result =  gsoa.GSOA_ProcessFiles(request.get('dataFilePath', ''),
                                     request.get('classFilePath', ''),
                                     request.get('gmtFilePath', ''),
                                     "/data/{}".format(request.data.get('email', 'results_txt')), **args)