using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace WebApplication1.Models
{
    public interface ICalculator
    {
        int Add(int num1, int num2);
        int Mul(int num1, int num2);
        int Sq(int num1);
    }

    public class Calculator : ICalculator
    {

        public int Add(int num1, int num2)
        {
            int result = num1 + num2;
            return result;
        }

        public int Mul(int num1, int num2)
        {
            int result = num1 * num2;
            //int result = num1 * num2 + 1;
            return result;
        }

        public int Sq(int num1)
        {
//            int result = num1 * num1 + 3;
            int result = num1 * num1;
            return result;
        }
    }
}
