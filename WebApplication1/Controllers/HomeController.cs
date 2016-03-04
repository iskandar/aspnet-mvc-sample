using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Configuration;
using System.Collections;

namespace WebApplication1.Controllers
{
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            ViewBag.Hostname = Environment.MachineName;
            ViewBag.ApplicationVersion = ConfigurationManager.AppSettings["ApplicationVersion"];
            ViewBag.Environment = ConfigurationManager.AppSettings["Environment"];
            ViewBag.BuildNumber = ConfigurationManager.AppSettings["BuildNumber"];
            ViewBag.BuildHash = ConfigurationManager.AppSettings["BuildHash"];
            ViewBag.ShortBuildHash = ConfigurationManager.AppSettings["BuildHash"].Substring(0, 8);
            ViewBag.BuildDate = ConfigurationManager.AppSettings["BuildDate"];
            ViewBag.BuildUrl = ConfigurationManager.AppSettings["BuildUrl"];
            ViewBag.DeployNumber = ConfigurationManager.AppSettings["DeployNumber"];
            ViewBag.DeployDate = ConfigurationManager.AppSettings["DeployDate"];
            ViewBag.DeployUrl = ConfigurationManager.AppSettings["DeployUrl"];

            var mvcName = typeof(Controller).Assembly.GetName();
            var isMono = Type.GetType("Mono.Runtime") != null;

            ViewBag.MvcVersion = mvcName.Version.Major + "." + mvcName.Version.Minor;
            ViewBag.Runtime = (isMono ? "Mono" : ".NET");
            ViewBag.ClrVersion = Environment.Version.ToString();

            var dict = Environment.GetEnvironmentVariables();
            var stringList = new List<String>();

            foreach (DictionaryEntry de in dict) {
                Console.WriteLine("  {0} = {1}", de.Key, de.Value);
                stringList.Add(de.Key + " = " + de.Value);
            }
            stringList.Sort();
            ViewData["EnvironmentVars"] = stringList;

            return View();
        }

        public ActionResult About()
        {
            ViewBag.Message = "Your application description page.";

            return View();
        }

        public ActionResult Contact()
        {
            ViewBag.Message = "Your contact page.";

            return View();
        }
    }
}