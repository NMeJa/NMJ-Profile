using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Management.Automation.Subsystem;
using System.Management.Automation.Subsystem.Prediction;
using System.Threading;

namespace NMJ.History
{
    public sealed class AtuinPredictor : ICommandPredictor
    {
        public static readonly Guid PredictorId = new Guid("9f3c2e1a-6b84-4d0e-a7c5-1b8e9f0a2d33");

        private static readonly object CacheLock = new object();
        private static string _cacheKey = "";
        private static List<string> _cacheHits;
        private static long _cacheTicks;
        private static HashSet<string> _forget;
        private static DateTime _forgetMtime = DateTime.MinValue;

        public Guid Id { get { return PredictorId; } }
        public string Name { get { return "NMJ.Atuin"; } }
        public string Description { get { return "Atuin history ranked by directory and prefix"; } }

        public SuggestionPackage GetSuggestion(PredictionClient client, PredictionContext context, CancellationToken cancellationToken)
        {
            try
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    return default(SuggestionPackage);
                }

                string input = "";
                if (context != null && context.InputAst != null && context.InputAst.Extent != null)
                {
                    input = context.InputAst.Extent.Text ?? "";
                }
                if (string.IsNullOrWhiteSpace(input) || input.Length < 2)
                {
                    return default(SuggestionPackage);
                }

                string cwd = Environment.CurrentDirectory ?? "";
                List<string> hits = GetRanked(input, cwd);
                if (hits == null || hits.Count == 0)
                {
                    return default(SuggestionPackage);
                }

                var suggestions = new List<PredictiveSuggestion>(hits.Count);
                for (int i = 0; i < hits.Count; i++)
                {
                    suggestions.Add(new PredictiveSuggestion(hits[i]));
                }
                return new SuggestionPackage(suggestions);
            }
            catch
            {
                return default(SuggestionPackage);
            }
        }

        public bool CanAcceptFeedback(PredictionClient client, PredictorFeedbackKind feedback)
        {
            return false;
        }

        public void OnSuggestionDisplayed(PredictionClient client, uint session, int countOrIndex) { }
        public void OnSuggestionAccepted(PredictionClient client, uint session, string acceptedSuggestion) { }
        public void OnCommandLineAccepted(PredictionClient client, IReadOnlyList<string> history) { }
        public void OnCommandLineExecuted(PredictionClient client, string commandLine, bool success) { }

        public static void InvalidateCache()
        {
            lock (CacheLock)
            {
                _cacheKey = "";
                _cacheHits = null;
                _forget = null;
                _forgetMtime = DateTime.MinValue;
            }
        }

        private static List<string> GetRanked(string query, string cwd)
        {
            string key = cwd + "\n" + query;
            long now = Environment.TickCount64;
            lock (CacheLock)
            {
                if (_cacheHits != null && _cacheKey == key && (now - _cacheTicks) < 400)
                {
                    return _cacheHits;
                }
            }

            HashSet<string> forgotten = LoadForget();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            var ranked = new List<string>();

            Collect(ranked, seen, forgotten, query, cwd, true, 12);
            if (ranked.Count < 8)
            {
                Collect(ranked, seen, forgotten, query, cwd, false, 12);
            }

            if (ranked.Count > 12)
            {
                ranked = ranked.GetRange(0, 12);
            }

            lock (CacheLock)
            {
                _cacheKey = key;
                _cacheHits = ranked;
                _cacheTicks = now;
            }
            return ranked;
        }

        private static void Collect(List<string> ranked, HashSet<string> seen, HashSet<string> forgotten, string query, string cwd, bool cwdOnly, int limit)
        {
            List<string> rows = RunAtuinSearch(query, cwdOnly ? cwd : null, limit);
            for (int i = 0; i < rows.Count; i++)
            {
                string cmd = rows[i];
                if (string.IsNullOrWhiteSpace(cmd)) { continue; }
                if (!cmd.StartsWith(query, StringComparison.OrdinalIgnoreCase)) { continue; }
                if (forgotten != null && forgotten.Contains(cmd)) { continue; }
                if (!seen.Add(cmd)) { continue; }
                ranked.Add(cmd);
            }
        }

        private static List<string> RunAtuinSearch(string query, string cwd, int limit)
        {
            var result = new List<string>();
            try
            {
                var psi = new ProcessStartInfo();
                psi.FileName = "atuin";
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.CreateNoWindow = true;
                psi.ArgumentList.Add("search");
                psi.ArgumentList.Add("--limit");
                psi.ArgumentList.Add(limit.ToString());
                psi.ArgumentList.Add("--format");
                psi.ArgumentList.Add("{command}");
                psi.ArgumentList.Add("--search-mode");
                psi.ArgumentList.Add("prefix");
                if (!string.IsNullOrEmpty(cwd))
                {
                    psi.ArgumentList.Add("--cwd");
                    psi.ArgumentList.Add(cwd);
                }
                psi.ArgumentList.Add("--");
                psi.ArgumentList.Add(query);

                using (var process = Process.Start(psi))
                {
                    if (process == null) { return result; }
                    if (!process.WaitForExit(150))
                    {
                        try { process.Kill(true); } catch { }
                        return result;
                    }
                    string output = process.StandardOutput.ReadToEnd();
                    if (string.IsNullOrEmpty(output)) { return result; }
                    string[] lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    for (int i = 0; i < lines.Length; i++)
                    {
                        result.Add(lines[i]);
                    }
                }
            }
            catch
            {
            }
            return result;
        }

        private static HashSet<string> LoadForget()
        {
            string path = Environment.GetEnvironmentVariable("NMJ_HISTORY_FORGET");
            if (string.IsNullOrEmpty(path))
            {
                string config = Environment.GetEnvironmentVariable("NMJ_CONFIG");
                if (string.IsNullOrEmpty(config))
                {
                    config = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nmj");
                }
                path = Path.Combine(config, "history-forget.txt");
            }

            DateTime mtime = DateTime.MinValue;
            try
            {
                if (File.Exists(path))
                {
                    mtime = File.GetLastWriteTimeUtc(path);
                }
            }
            catch
            {
            }

            lock (CacheLock)
            {
                if (_forget != null && _forgetMtime == mtime)
                {
                    return _forget;
                }
            }

            var set = new HashSet<string>(StringComparer.Ordinal);
            try
            {
                if (File.Exists(path))
                {
                    foreach (string line in File.ReadAllLines(path))
                    {
                        if (!string.IsNullOrWhiteSpace(line))
                        {
                            set.Add(line);
                        }
                    }
                }
            }
            catch
            {
            }

            lock (CacheLock)
            {
                _forget = set;
                _forgetMtime = mtime;
            }
            return set;
        }
    }
}
