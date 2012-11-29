<%@ WebHandler Language="C#" Class="proxy" %>
/*
 | Version 10.1.1
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
/*
  This proxy page does not have any security checks. It is highly recommended
  that a user deploying this proxy page on their web server, add appropriate
  security checks, for example checking request path, username/password, target
  url, etc.
*/
using System;
using System.IO;
using System.Web;
using System.Collections.Generic;
using System.Text;
using System.Xml.Serialization;
using System.Web.Caching;
//============================================================================================================================//

/// <summary>
/// Forwards requests to an ArcGIS Server REST resource. Uses information in
/// the proxy.config file to determine properties of the server.
/// </summary>
public class proxy : IHttpHandler
{
    const bool cShowAuthXHeaders = true;

    public void ProcessRequest (HttpContext context)
    {
        HttpRequest originalRequest = context.Request;
        HttpResponse response = context.Response;

        // Read config file
        ProxyConfig config = ProxyConfig.GetCurrentConfig();
        if(null == config)
        {
            response.StatusCode = 500;
            response.StatusDescription = "Proxy configuration not available";
            response.End();
            return;
        }

        // Check that the application's server matches the config file
        string applicationURL = originalRequest.Url.Scheme + "://" + originalRequest.Url.Host;
        string[] segs = originalRequest.Url.Segments;
        for(int i = 0; i < (segs.Length - 1); ++i)
        {
            applicationURL += segs[i];
        }
        applicationURL = applicationURL.ToLower();
        if(applicationURL.EndsWith("/")) applicationURL = applicationURL.Substring(0, applicationURL.Length - 1);

        string configAppURL = config.applicationURL.ToLower();
        if (configAppURL.EndsWith("/")) configAppURL = configAppURL.Substring(0, configAppURL.Length - 1);

        if (applicationURL != configAppURL)
        {
            response.StatusCode = 500;
            response.StatusDescription = "Unsupported application URL";
            response.End();
            return;
        }

        // Get the URL requested by the client (take the entire querystring at once to handle the case of the
        // URL itself containing querystring parameters); lop off initial question mark of query string, then
        // lop off http*:// so that we can handle both unsecure and secure services
        string dataURL = 1 < originalRequest.Url.Query.Length ? originalRequest.Url.Query.Substring(1) : "";
        int iProtocol = dataURL.IndexOf("//");
        string testDataURL = (0 <= iProtocol? dataURL.Substring(iProtocol + 2) : dataURL).ToLower();

        // Check that the data URL matches the config file
        var ok = false;
        var authenticate = true;
        foreach(dataUrlPrefix item in config.dataUrlPrefixes)
        {
            ok |= testDataURL.StartsWith(item.url.ToLower());
            if (ok)
            {
                if(null != item.authenticate && "false" == item.authenticate.ToLower())
                {
                    authenticate = false;
                }
                break;
            }
        }
        if (!ok)
        {
            response.StatusCode = 500;
            response.StatusDescription = "Unsupported data URL";
            response.End();
            return;
        }

        // If we need to authenticate, can we get the authentication spec from the cache?
        string username = "";
        bool usedCache = true;//???
        string authExpiration = "";//???
        AuthenticationSpec authSpec = null;
        if(authenticate)
        {
            authSpec = HttpRuntime.Cache["authentication"] as AuthenticationSpec;
            if (authSpec == null)
            {
                usedCache = false;//???
                // No spec available--we'll have to generate one

                // Pick a username; we can have multiple to spread out the load
                string[] usernames = config.username.Split(new Char[] {','});
                username = usernames[0];
                if(1 < usernames.Length)
                {
                    username = usernames[(new Random()).Next(usernames.Length)];
                }

                // Post the authentication request
                System.Net.HttpWebRequest authenticationReq =
                    (System.Net.HttpWebRequest)System.Net.HttpWebRequest.Create(config.authenticationUrl);
                authenticationReq.Method = "POST";
                authenticationReq.ContentType = "application/x-www-form-urlencoded; charset=UTF-8";
                authenticationReq.ServicePoint.Expect100Continue = false;

                string postData =
                    "referer=" + config.applicationURL +
                    "&username=" + username +
                    "&password=" + config.password +
                    "&expiration=" + config.tokenDurationMinutes.ToString() +
                    "&f=pjson";
                byte[] postBytes = UTF8Encoding.UTF8.GetBytes(postData);
                authenticationReq.ContentLength = postBytes.Length;
                using (Stream outputStream = authenticationReq.GetRequestStream())
                {
                    outputStream.Write(postBytes, 0, postBytes.Length);
                }

                // Read the authentication response
                System.Net.HttpWebResponse authenticationResponse = null;
                try
                {
                    authenticationResponse = (System.Net.HttpWebResponse)authenticationReq.GetResponse();
                }
                catch (System.Net.WebException)
                {
                    authenticationResponse = null;
                }

                if (authenticationResponse != null)
                {
                    try
                    {
                        using (Stream byteStream = authenticationResponse.GetResponseStream())
                        {
                            System.Runtime.Serialization.Json.DataContractJsonSerializer jsonSer =
                                new System.Runtime.Serialization.Json.DataContractJsonSerializer(typeof(AuthenticationSpec));
                            authSpec = (AuthenticationSpec)jsonSer.ReadObject(byteStream);
                        }
                    }
                    catch(Exception ex)
                    {
                        authSpec = null;
                    }
                    authenticationResponse.Close();
                }
            }

            // Cache the authentication
            if (authSpec != null && null == authSpec.error)
            {
                DateTime expiresDate = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMilliseconds(authSpec.expires);
                HttpRuntime.Cache.Insert("authentication", authSpec, null, expiresDate, Cache.NoSlidingExpiration);

                authExpiration = expiresDate.ToShortDateString() + " " + expiresDate.ToShortTimeString() + " UTC";//???
            }
            else
            {
                response.StatusCode = 500;
                response.StatusDescription = "Authentication failed";
                response.End();
                return;
            }
        }

        // Create the proxied URL
        if (dataURL.Contains("?"))
        {
            // Check that the data URL doesn't contain extra question marks
            int iQ = dataURL.IndexOf("?");
            for (;;)
            {
                if(dataURL.Length <= ++iQ) break;
                iQ = dataURL.IndexOf("?", iQ);
                if(0 > iQ) break;
                dataURL = dataURL.Remove(iQ, 1).Insert(iQ, "&");
            };

            if(authenticate)
            {
                dataURL += "&token=" + authSpec.token;
            }
        }
        else if(authenticate)
        {
            dataURL += "?token=" + authSpec.token;
        }

        // Set up the user request
        System.Net.HttpWebRequest proxiedReq = (System.Net.HttpWebRequest)System.Net.HttpWebRequest.Create(dataURL);
        proxiedReq.Method = context.Request.HttpMethod;
        proxiedReq.ServicePoint.Expect100Continue = false;

        // Set body of request for POST requests
        if (context.Request.InputStream.Length > 0)
        {
            byte[] bytes = new byte[context.Request.InputStream.Length];
            context.Request.InputStream.Read(bytes, 0, (int)context.Request.InputStream.Length);
            proxiedReq.ContentLength = bytes.Length;

            string ctype = context.Request.ContentType;
            if (String.IsNullOrEmpty(ctype)) {
                proxiedReq.ContentType = "application/x-www-form-urlencoded";
            }
            else {
                proxiedReq.ContentType = ctype;
            }

            using (Stream outputStream = proxiedReq.GetRequestStream())
            {
                outputStream.Write(bytes, 0, bytes.Length);
            }
        }

        // Send the user request to the server
        System.Net.HttpWebResponse serverResponse = null;
        try
        {
            serverResponse = (System.Net.HttpWebResponse)proxiedReq.GetResponse();
        }
        catch (System.Net.WebException webExc)
        {
            response.StatusCode = 500;
            response.StatusDescription = webExc.Status.ToString();
            response.Write(webExc.Message);
            response.Write("<br />");
            response.Write(webExc.Response);
            response.End();
            return;
        }

        // Set up the response to the client
        if (serverResponse != null)
        {
            response.ContentType = serverResponse.ContentType;
            if(authenticate && cShowAuthXHeaders)//???
            {
                if(!usedCache) response.Headers["X-User"] = username;
                response.Headers["X-Cached"] = usedCache.ToString();
                response.Headers["X-AuthExpiration"] = authExpiration;
            }
            try
            {
                using (Stream byteStream = serverResponse.GetResponseStream())
                {

                    // Text response
                    if (serverResponse.ContentType.Contains("text") ||
                        serverResponse.ContentType.Contains("json"))
                    {
                        using (StreamReader sr = new StreamReader(byteStream))
                        {
                            string strResponse = sr.ReadToEnd();
                            response.Write(strResponse);
                        }
                    }
                    else
                    {
                        // Binary response (image, lyr file, other binary file)
                        BinaryReader br = new BinaryReader(byteStream);

                        // If the server provides the Content Length, use it.
                        // But just because the value is zero doesn't mean that the server
                        // didn't send us anything; cf ArcGIS.com & item thumbnails.
                        int numBytes = (int)serverResponse.ContentLength;
                        if (0 >= numBytes) numBytes = 4096;

                        // Read until the response is empty
                        int bytesRead = 0;
                        do
                        {
                            byte[] outb = br.ReadBytes(numBytes);
                            bytesRead = outb.Length;

                            // Send the image to the client
                            if (0 < bytesRead) response.OutputStream.Write(outb, 0, bytesRead);
                        } while (0 < bytesRead);

                        br.Close();
                    }
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                response.StatusDescription = ex.Message.ToString();
                response.Write(ex.Message);
            }
            serverResponse.Close();
        }

        response.End();
    }

    public bool IsReusable
    {
        get {
            return false;
        }
    }
}

//============================================================================================================================//

/// <summary>
/// Represents the contents of the config file and provides routines for accessing those contents.
/// </summary>
[XmlRoot("ProxyConfig")]
public class ProxyConfig
{
    #region Static Members

    private static object _lockobject = new object();

    public static ProxyConfig LoadProxyConfig(string fileName)
    {
        ProxyConfig config = null;

        lock (_lockobject)
        {
            if (System.IO.File.Exists(fileName))
            {
                XmlSerializer reader = new XmlSerializer(typeof(ProxyConfig));
                using (System.IO.StreamReader file = new System.IO.StreamReader(fileName))
                {
                    config = (ProxyConfig)reader.Deserialize(file);
                }
            }
        }

        return config;
    }

    public static ProxyConfig GetCurrentConfig()
    {
        ProxyConfig config = HttpRuntime.Cache["proxyConfig"] as ProxyConfig;
        if (config == null)
        {
            string fileName = GetFilename(HttpContext.Current);
            config = LoadProxyConfig(fileName);

            if (config != null)
            {
                CacheDependency dep = new CacheDependency(fileName);
                HttpRuntime.Cache.Insert("proxyConfig", config, dep);
            }
        }

        return config;
    }

    public static string GetFilename(HttpContext context)
    {
        return context.Server.MapPath("~/proxy.config");
    }
    #endregion


    [XmlElement("applicationURL")]
    public string applicationURL;

    [XmlElement("authenticationUrl")]
    public string authenticationUrl;

    // http://stackoverflow.com/a/1052565
    [XmlArray("dataUrlPrefixes")]
    [XmlArrayItem("dataUrlPrefix")]
    public dataUrlPrefix[] dataUrlPrefixes;

    [XmlElement("username")]
    public string username;

    [XmlElement("password")]
    public string password;

    [XmlElement("tokenDurationMinutes")]
    public int tokenDurationMinutes;
}

[XmlRoot("dataUrlPrefix")]
public class dataUrlPrefix
{
    [XmlAttribute("authenticate")]
    public string authenticate;

    [XmlAttribute("url")]
    public string url;
}

//============================================================================================================================//

/// <summary>
/// Represents the contents of the authentication specification returned from arcgis.com.
/// </summary>
[System.Runtime.Serialization.DataContract]
public class AuthenticationSpec
{
    [System.Runtime.Serialization.DataMember]
    public string token;

    [System.Runtime.Serialization.DataMember]
    public long expires;

    [System.Runtime.Serialization.DataMember]
    public bool ssl;

    [System.Runtime.Serialization.DataMember]
    public object error;
}