var exec = require('cordova/exec'),
  channel = require('cordova/channel'),

  // Reference name for the plugin
  PLUGIN_NAME = 'UniversalLinks',

  // Default event name that is used by the plugin
  DEFAULT_EVENT_NAME = 'didLaunchAppFromLink';

// Plugin methods on the native side that can be called from JavaScript
pluginNativeMethod = {
  SUBSCRIBE: 'jsSubscribeForEvent',
  UNSUBSCRIBE: 'jsUnsubscribeFromEvent',
  GET_LAUNCH_URL: 'jsGetLaunchUrl'
};

var universalLinks = {

  /**
   * Subscribe to event.
   * If plugin already captured that event - callback will be called immidietly.
   *
   * @param {String} eventName - name of the event you are subscribing on; if null - default plugin event is used
   * @param {Function} callback - callback that is called when event is captured
   */
  subscribe: function(eventName, callback) {
    if (!callback) {
      console.warn('Universal Links: can\'t subscribe to event without a callback');
      return Promise.reject("no callback");
    }

    if (!eventName) {
      eventName = DEFAULT_EVENT_NAME;
    }

    return new Promise((resolve, reject) => {
      var innerCallback = function(msg) {
        if (msg !== "") {
          callback(msg.data);
        }
        resolve();
      };

      var errorCallback = function(err) {
        reject(err);
      };

      exec(innerCallback, errorCallback, PLUGIN_NAME, pluginNativeMethod.SUBSCRIBE, [eventName]);
    });
  },

  /**
   * Unsubscribe from the event.
   *
   * @param {String} eventName - from what event we are unsubscribing
   */
  unsubscribe: function(eventName) {
    if (!eventName) {
      eventName = DEFAULT_EVENT_NAME;
    }

    exec(null, null, PLUGIN_NAME, pluginNativeMethod.UNSUBSCRIBE, [eventName]);
  },

  getLaunchUrl: function() {
    return new Promise((resolve, reject) => {
      exec(data => {
        resolve(data.url);
      }, error => {
        reject(error);
      },
      PLUGIN_NAME, pluginNativeMethod.GET_LAUNCH_URL, []);
    });
  }
};

module.exports = universalLinks;
