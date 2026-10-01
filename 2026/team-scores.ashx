<%@ WebHandler Language="C#" Class="IESATeamScores" %>
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Caching;
using System.Web.Script.Serialization;

public class IESATeamScores : IHttpHandler
{
    private static readonly object RefreshLock = new object();
    private static readonly Regex SourcePattern = new Regex(
        @"^https://www\.iesa\.org/activities/memberStats\.asp\?SchoolID=(\d+)&ActivityCode=GBK&GradeLevel=([78])$",
        RegexOptions.IgnoreCase);
    private static readonly Regex GamePattern = new Regex(
        @"(?is)<td class='ListData'>(.*?)</td>\s*<td class='ListData-R'>(.*?)</td>");

    public bool IsReusable { get { return true; } }

    public void ProcessRequest(HttpContext context)
    {
        context.Response.ContentType = "application/json";
        context.Response.Cache.SetCacheability(HttpCacheability.NoCache);
        context.Response.Cache.SetNoStore();
        try {
            Respond(context);
        } catch (Exception ex) {
            context.Trace.Warn("IESA scores", "Unhandled score lookup failure", ex);
            context.Response.Clear();
            context.Response.ContentType = "application/json";
            Error(context, 500, "The score lookup failed unexpectedly. Existing scores were not changed.");
        }
    }

    private static void Respond(HttpContext context)
    {
        string origin = context.Request.Headers["Origin"];
        if (context.Request.HttpMethod != "POST" ||
            origin != context.Request.Url.GetLeftPart(UriPartial.Authority) ||
            context.Request.ContentLength > 512) {
            Error(context, 403, "Use the team score button on this site.");
            return;
        }

        string grade = context.Request.Form["grade"];
        string team = context.Request.Form["team"];
        if ((grade != "7th" && grade != "8th") || String.IsNullOrEmpty(team) || team.Length > 160) {
            Error(context, 400, "Select a valid team and grade.");
            return;
        }

        ScoreCache siteCache;
        try {
            siteCache = ReadCache(context.Server.MapPath("scores-" + grade + ".json"));
        } catch (IOException ex) {
            context.Trace.Warn("IESA scores", "Could not read the nightly score cache", ex);
            Error(context, 503, "The site's nightly score cache is unavailable.");
            return;
        } catch (ArgumentException ex) {
            context.Trace.Warn("IESA scores", "Invalid nightly score cache", ex);
            Error(context, 503, "The site's nightly score cache is invalid.");
            return;
        } catch (InvalidOperationException ex) {
            context.Trace.Warn("IESA scores", "Invalid nightly score cache", ex);
            Error(context, 503, "The site's nightly score cache is invalid.");
            return;
        }
        ScoreTeam school;
        if (siteCache == null || siteCache.teams == null ||
            !siteCache.teams.TryGetValue(team, out school) || school == null) {
            Error(context, 404, "This team is not in the site's score cache.");
            return;
        }
        Match source = SourcePattern.Match(school.sourceUrl ?? "");
        if (!source.Success || source.Groups[2].Value != grade.Substring(0, 1)) {
            Error(context, 503, "The official source for this team is invalid.");
            return;
        }

        string key = "iesa-2026-live-" + grade + "-" + source.Groups[1].Value;
        TeamResult result = HttpRuntime.Cache[key] as TeamResult;
        if (result == null) {
            lock (RefreshLock) {
                result = HttpRuntime.Cache[key] as TeamResult;
                if (result == null) {
                    try {
                        result = Fetch(team, grade, source.Groups[1].Value);
                    } catch (WebException ex) {
                        context.Trace.Warn("IESA scores", "IESA request failed", ex);
                        Error(context, 502, "IESA could not be reached. Existing scores were not changed.");
                        return;
                    } catch (IOException ex) {
                        context.Trace.Warn("IESA scores", "IESA response could not be read", ex);
                        Error(context, 502, "IESA's response could not be read. Existing scores were not changed.");
                        return;
                    } catch (InvalidDataException ex) {
                        context.Trace.Warn("IESA scores", "IESA returned an unexpected page", ex);
                        Error(context, 502, "IESA returned an unexpected page. Existing scores were not changed.");
                        return;
                    }
                    HttpRuntime.Cache.Insert(key, result, null, DateTime.UtcNow.AddMinutes(5),
                        Cache.NoSlidingExpiration);
                }
            }
        }
        context.Response.Write(new JavaScriptSerializer().Serialize(result));
    }

    private static ScoreCache ReadCache(string path)
    {
        // The nightly refresh replaces this file, so a single failed read may simply
        // have caught the swap. Retry briefly before reporting the cache as unusable.
        for (int attempt = 0; ; attempt++) {
            try {
                return new JavaScriptSerializer().Deserialize<ScoreCache>(File.ReadAllText(path));
            } catch (IOException) {
                if (attempt == 2) { throw; }
            } catch (ArgumentException) {
                if (attempt == 2) { throw; }
            }
            System.Threading.Thread.Sleep(150);
        }
    }

    private static TeamResult Fetch(string team, string grade, string schoolId)
    {
        ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
        string sourceUrl = "https://www.iesa.org/activities/memberStats.asp?SchoolID=" +
            schoolId + "&ActivityCode=GBK&GradeLevel=" + grade.Substring(0, 1);
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(sourceUrl);
        request.Timeout = 15000;
        request.ReadWriteTimeout = 15000;
        request.AllowAutoRedirect = false;
        request.UserAgent = "IESA-2026-bracket/1.0";
        string html;
        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        using (StreamReader reader = new StreamReader(response.GetResponseStream(), Encoding.UTF8, true)) {
            StringBuilder content = new StringBuilder();
            char[] buffer = new char[4096];
            int count;
            while ((count = reader.Read(buffer, 0, buffer.Length)) > 0) {
                content.Append(buffer, 0, count);
                if (content.Length > 512000) {
                    throw new InvalidDataException("Oversized IESA page");
                }
            }
            html = content.ToString();
        }
        if (!html.Contains("IESA Member School Contests") ||
            PlainText(html).IndexOf(team.Replace(" (Co-op)", ""),
                StringComparison.OrdinalIgnoreCase) < 0) {
            throw new InvalidDataException("IESA page does not identify the requested school");
        }

        List<Game> games = new List<Game>();
        int wins = 0;
        int losses = 0;
        string schoolName = Regex.Escape(team.Replace(" (Co-op)", ""));
        foreach (Match match in GamePattern.Matches(html)) {
            string opponent = PlainText(match.Groups[1].Value);
            string score = PlainText(match.Groups[2].Value).ToUpperInvariant();
            games.Add(new Game { opponent = opponent, score = score });
            if (Regex.IsMatch(opponent, "^" + schoolName + @".*\sdef\.", RegexOptions.IgnoreCase)) {
                wins++;
            } else if (Regex.IsMatch(opponent, @"\sdef\..*" + schoolName + "$",
                RegexOptions.IgnoreCase)) {
                losses++;
            }
        }
        return new TeamResult {
            team = team,
            sourceUrl = sourceUrl,
            updatedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm"),
            record = new Record { wins = wins, losses = losses, completed = wins + losses },
            games = games
        };
    }

    private static string PlainText(string html)
    {
        return Regex.Replace(HttpUtility.HtmlDecode(Regex.Replace(html, "<[^>]+>", " ")),
            @"\s+", " ").Trim();
    }

    private static void Error(HttpContext context, int status, string message)
    {
        context.Response.StatusCode = status;
        context.Response.TrySkipIisCustomErrors = true;
        context.Response.Write(new JavaScriptSerializer().Serialize(new { error = message }));
    }

    public class ScoreCache
    {
        public Dictionary<string, ScoreTeam> teams { get; set; }
    }

    public class ScoreTeam
    {
        public string sourceUrl { get; set; }
    }

    public class TeamResult
    {
        public string team { get; set; }
        public string sourceUrl { get; set; }
        public string updatedAt { get; set; }
        public Record record { get; set; }
        public List<Game> games { get; set; }
    }

    public class Record
    {
        public int wins { get; set; }
        public int losses { get; set; }
        public int completed { get; set; }
    }

    public class Game
    {
        public string opponent { get; set; }
        public string score { get; set; }
    }
}
