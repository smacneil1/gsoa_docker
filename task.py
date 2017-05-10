import tasktiger
from redis import Redis 
from rpy2.robjects.packages import importr
import rpy2.robjects as ro

#import GSOA from R into Python
gsoa = importr('GSOA')

# connect to the database
conn = Redis(host="redis://redis")
# picking stuff off the queque and running it
tiger = tasktiger.TaskTiger(connection=conn)


NECESSARY_FIELDS = ['dataFilePath', 'classFilePath', 'gmtFilePath', 'outFilePath']
ACCEPTED_FIELDS = ['classificationAlgorithm', 'numCrossValidationFolds', 'numRandomIterations',
                   'numCores', 'removePercentLowestExpr', 'removePercentLowestVar'] + NECESSARY_FIELDS

# tiger task that gets run after picking off queque
@tiger.task()

# function that calls gsoa
def call_gsoa(request):
    gsoa = importr('GSOA')
    conn = Redis(host="redis://redis")
    tiger = tasktiger.TaskTiger(connection=conn)
    # getting data from the queque
    args = request.data.copy()
    # allows other arugments to be passed to gsoa
    for field in NECESSARY_FIELDS:
        args.pop(field)
    # make sure that there is data
    if len(str(request.data.get('dataFilePath'))) < 2:
        return "no data"
    # prints to logs
    print("result: {}".format(request.data))
    print("email: {}".format(request.data.get('email', 'results_txt')))       
    # call gsoa
    result =  gsoa.GSOA_ProcessFiles(request.get('dataFilePath', ''),
                                     request.get('classFilePath', ''),
                                     request.get('gmtFilePath', ''),
                                     "/data/{}".format(request.data.get('email', 'results_txt')), **args)
