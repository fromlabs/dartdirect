Ext.define('FromLabs.extends.direct.DartProvider', {
  extend: "Ext.direct.RemotingProvider",
  alias:  'direct.dartprovider',

  sendRequest: function(data) {
    var me = this,
        request, callData, params,
        i, len;

    request = {
        url: me.url,
        callback: me.onData,
        scope: me,
        transaction: data
    };

    if (Ext.isArray(data)) {
        callData = [];

        for (i = 0, len = data.length; i < len; ++i) {
            callData.push(me.getCallData(data[i]));
        }
    }
    else {
        callData = me.getCallData(data);
    }

    request.jsonData = callData;

    me.dartRequest(request);
  },

  sendFormRequest: function(transaction) {
    var me = this;

    dartRequest({
        url: me.url,
        params: transaction.params,
        callback: me.onData,
        scope: me,
        form: transaction.form,
        isUpload: transaction.isUpload,
        transaction: transaction
    });
  },

  dartRequest: function(request) {
    directCall(null, "embedded", "direct", Ext.JSON.encode(request.jsonData), function(jsonResponse, responseHeaders) {

      // TODO sfruttare i response headers

      var response = {
        responseText: Ext.JSON.decode(jsonResponse)
      };
      Ext.callback(request.callback, request.scope, [request, true, response]);
    });
  }
});
