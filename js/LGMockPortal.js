/*global dojo,js,setTimeout */
/*jslint sloppy: true */
/** @license
 | Copyright 2012 Esri
 |
 | Licensed under the Apache License, Version 2.0 (the "License");
 | you may not use this file except in compliance with the License.
 | You may obtain a copy of the License at
 |
 |    http://www.apache.org/licenses/LICENSE-2.0
 |
 | Unless required by applicable law or agreed to in writing, software
 | distributed under the License is distributed on an "AS IS" BASIS,
 | WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 | See the License for the specific language governing permissions and
 | limitations under the License.
 */
//============================================================================================================================//
dojo.provide("js.LGMockPortal");
dojo.declare("js.LGMockPortal", null, {

    /**
     * Constructs an LGMockPortal.
     * @constructor
     * @class
     * @name js.LGMockPortal
     * @classdesc
     * Builds and manages an object that can accumulate text and
     * objects.
     * <br>
     * <br> | Copyright 2012 Esri
     * <br> |
     * <br> | Licensed under the Apache License, Version 2.0 (the "License");
     * <br> | you may not use this file except in compliance with the License.
     * <br> | You may obtain a copy of the License at
     * <br> |
     * <br> | http://www.apache.org/licenses/LICENSE-2.0
     * <br> |
     * <br> | Unless required by applicable law or agreed to in writing, software
     * <br> | distributed under the License is distributed on an "AS IS" BASIS,
     * <br> | WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
     * <br> | See the License for the specific language governing permissions and
     * <br> | limitations under the License.
     * <br>
     * <br>Author Mike Tschudi
     * <br>Version 2012.4.m2 (10/26/2012)
     */
    constructor: function () {
    // input argument is portalUrl, but is not used
    },

    signIn: function () {
    // returns deferred, which sends logged-in user, of which only credential.token is needed
    // loggedInUser
    //   -- credential
    //        -- token
        var deferred = new dojo.Deferred();

        setTimeout(function () {
            var loggedInUser = {};
            loggedInUser.credential = {};
            loggedInUser.credential.token = "";
            deferred.callback(loggedInUser);
        });

        return deferred;
    },

    signOut: function () {
    // returns deferred, which sends portalInfo (not used)
        var deferred = new dojo.Deferred();

        setTimeout(function () {
            deferred.callback(null);
        });

        return deferred;
    },

    queryItems: function () {
    // input argument is params, but is not used
    // query criteria
    //     var params = {
    //         q: 'group:' + authenticatedGroup,
    //         num: 100  // max allowed value
    //     }
    // http://www.arcgis.com/sharing/rest/search?num=100&start=0&sortField=title&sortOrder=asc&q=group%3A9c63fc64e30c4c57a3b34c4b8a3da56e&f=json&token=<token>
    // returns deferred, which sends groupData (not used)
        var deferred = new dojo.Deferred();

        setTimeout(function () {
            deferred.callback(null);
        });

        return deferred;
    }

});
