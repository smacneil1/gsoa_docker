
from flask import request, url_for
from flask_api import FlaskAPI, status, exceptions
import tasktiger
from redis import Redis 
from gsoa_task import call_gsoa

# imports GSOA from R
app = FlaskAPI(__name__)
# redis stores all the quque information
conn = Redis(host="redis")
tiger = tasktiger.TaskTiger(connection=conn)
NECESSARY_FIELDS = ['dataFilePath', 'classFilePath', 'gmtFilePath', 'outFilePath']
ACCEPTED_FIELDS = ['classificationAlgorithm', 'numCrossValidationFolds', 'numRandomIterations',
                   'numCores', 'removePercentLowestExpr', 'removePercentLowestVar'] + NECESSARY_FIELDS


# makes sure the feilds are present 
def validate_input(request_data):
    if set(NECESSARY_FIELDS) - set(request_data.keys()):
        print("necessary fields not added")
    if set(ACCEPTED_FIELDS) - set(request_data.keys()) - set(ACCEPTED_FIELDS):
        print("invalid fields passed : {}".format(set(ACCEPTED_FIELDS) - set(request_data.keys()) - set(ACCEPTED_FIELDS)))
 
   
# puts gsoa jobs into the task tiger queque 
@app.route("/", methods=['GET', 'POST'])
def gsoa_process():
    """
    List or create notes.
    """
    if request.method == 'POST':
        if not request.data:
            return "no data"
        validate_input(request.data)
        #call_gsoa(request.data)
        tiger.delay(call_gsoa, kwargs={"request": request.data})
        if request.data.get("checkbox", "") == "checked":
             tiger.delay(call_gsoa_hallmarks, kwargs={"request": request.data})
        return 'Job sucessfully started'
        
    return 'test'


# startup your flask app
if __name__ == "__main__":
    app.run(host='0.0.0.0', debug=True)
