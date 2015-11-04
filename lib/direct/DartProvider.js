Ext.define('FromLabs.extends.direct.DartProvider', {
  extend: "Ext.direct.RemotingProvider",
  alias:  'direct.dartprovider',

    sendRequest : function(data) {
        var me = this,
            request = {
                url: me.getUrl(),
                callback: me.onData,
                scope: me,
                transaction: data,
                timeout: me.getTimeout()
            }, callData,
            enableUrlEncode = me.getEnableUrlEncode(),
            i = 0,
            ln, params;


        if (Ext.isArray(data)) {
            callData = [];
            for (ln = data.length; i < ln; ++i) {
                callData.push(me.getCallData(data[i]));
            }
        } else {
            callData = me.getCallData(data);
        }

        if (enableUrlEncode) {
            params = {};
            params[Ext.isString(enableUrlEncode) ? enableUrlEncode : 'data'] = Ext.encode(callData);
            request.params = params;
        } else {
            request.jsonData = callData;
        }

        // Ext.Ajax.request(request);
        me.customRequest(request);
    },

    sendFormRequest : function(transaction) {
        var me = this;

        // Ext.Ajax.request({
        me.customRequest({
            url: me.getUrl(),
            params: transaction.params,
            callback: me.onData,
            scope: me,
            form: transaction.form,
            isUpload: transaction.isUpload,
            transaction: transaction
        });
    },

    defaultRequest: function(request) {
        this.dartRequest(request);
    },

    customRequest: function(request) {
        this.defaultRequest(request);
    },

    dartRequest: function(options) {
      var headers = Ext.Ajax.getDefaultHeaders();

      directCall(null, "embedded", "direct", Ext.JSON.encode(options.jsonData), Ext.JSON.encode(headers), function(jsonResponse, responseHeaders) {

          // TODO sfruttare i response headers

          var response = {
              request: {
                  async: true,
                  headers: headers,
                  options: options
              },
              responseBytes: null,
              responseText: Ext.JSON.decode(jsonResponse),
              responseXML: null,
              status: 200,
              statusText: "OK"
          };

          Ext.callback(options.callback, options.scope, [options, true, response]);
      });
    }
});