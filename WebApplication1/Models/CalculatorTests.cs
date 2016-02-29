using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using NUnit.Framework;


namespace WebApplication1.Models
{
    [TestFixture]
    public class CalculatorTest
    {
        [Test]
        public void ShouldAddTwoNumbers()
        {
            ICalculator sut = new Calculator();
            int expectedResult = sut.Add(7, 8);
            Assert.That(expectedResult, Is.EqualTo(15));
        }

        [Test]
        public void ShouldMulTwoNumbers()
        {
            ICalculator sut = new Calculator();
            int expectedResult = sut.Mul(7, 8);
            Assert.That(expectedResult, Is.EqualTo(56));
        }

        [Test]
        public void ShouldSqOneNumber()
        {
            ICalculator sut = new Calculator();
            int expectedResult = sut.Sq(7);
            Assert.That(expectedResult, Is.EqualTo(49));
        }

    }
}