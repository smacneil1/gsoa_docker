
from flask import request, url_for
from flask_api import FlaskAPI, status, exceptions
from rpy2.robjects.packages import importr
import rpy2.robjects as ro


gsoa = importr('GSOA')
app = FlaskAPI(__name__)

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
        args = request.data.copy()
        for field in NECESSARY_FIELDS:
            args.pop(field)
        if len(str(request.data.get('dataFilePath'))) < 2:
            return "no data"
        app.logger.info("result: {}".format(request.data))
        app.logger.info("email: {}".format(request.data.get('email', 'results_txt')))       
        result =  gsoa.GSOA_ProcessFiles(request.data.get('dataFilePath', ''),
                                         request.data.get('classFilePath', ''),
                                         request.data.get('gmtFilePath', ''),
                                         "/data/{}".format(request.data.get('email', 'results_txt')), **args)
        return 'Job sucessfully started: {}'.format(result)
        
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
