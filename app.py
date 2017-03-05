
from flask import request, url_for
from flask_api import FlaskAPI, status, exceptions
import tasktiger
from redis import Redis 
from gsoa_task import call_gsoa
# imports GSOA from R

app = FlaskAPI(__name__)
conn = Redis(host="redis")
tiger = tasktiger.TaskTiger(connection=conn)
NECESSARY_FIELDS = ['dataFilePath', 'classFilePath', 'gmtFilePath', 'outFilePath']
ACCEPTED_FIELDS = ['classificationAlgorithm', 'numCrossValidationFolds', 'numRandomIterations',
                   'numCores', 'removePercentLowestExpr', 'removePercentLowestVar'] + NECESSARY_FIELDS

def validate_input(request_data):
    if set(NECESSARY_FIELDS) - set(request_data.keys()):
        print("necessary fields not added")
    if set(ACCEPTED_FIELDS) - set(request_data.keys()) - set(ACCEPTED_FIELDS):
        print("invalid fields passed : {}".format(set(ACCEPTED_FIELDS) - set(request_data.keys()) - set(ACCEPTED_FIELDS)))
    
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
        return 'Job sucessfully started'
        
    return 'test'



@app.route("/<int:key>/", methods=['GET', 'PUT', 'DELETE'])
def notes_detail(key):
    """
    Retrieve, update or delete note instances.
    """
    if request.method == 'PUT':
        note = str(request.data.get('text', ''))
        notes[key] = note
        return note_repr(key)

    elif request.method == 'DELETE':
        notes.pop(key, None)
        return '', status.HTTP_204_NO_CONTENT

    # request.method == 'GET'
    if key not in notes:
        raise exceptions.NotFound()
    return note_repr(key)


if __name__ == "__main__":
    app.run(host='0.0.0.0', debug=True)
