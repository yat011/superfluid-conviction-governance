


def cal(n, y_0, x_0, beta, alpha):
    result = y_0
    for i in range(1, n+1):
        result = result * alpha + x_0 + i * beta
        print(i, result)

def cal_closeform(n, y_0, x_0, beta, alpha):
    result = alpha ** n * y_0  + x_0 * (1-alpha ** n) / ( 1- alpha)
    # result += beta * (n* (1-alpha ** n) / ( 1- alpha)  -  (alpha - alpha ** n)/(1- alpha) ** 2)
    # result += beta * (n* (1-alpha ** n) / ( 1- alpha)) - beta * (alpha - alpha ** n)/(1- alpha) ** 2

    C_n = n* (1-alpha ** n) / ( 1- alpha) -  (alpha - alpha ** n)/(1-alpha) ** 2 + (n-1)/(1-alpha) * alpha** n

    print("c1", n* (1-alpha ** n) / ( 1- alpha) )
    print("c2", n* (1-alpha ** n) / ( 1- alpha) +  (n-1)/(1-alpha) * alpha** n )
    print("c3", C_n )

    result += C_n * beta
    # result += beta * (n* (1-alpha ** n) / ( 1- alpha)) - beta / ( 1- alpha) * ( (alpha - alpha ** n)/(1- alpha) - ( n-1) * alpha ** n)
    # result += beta * (n* (1-alpha ** n) / ( 1- alpha)) - beta * sum([t * (alpha ** t) for t in range(n)])
    # result += beta * n * sum ([alpha ** t for t in range(n)]) - beta * sum([t * (alpha ** t) for t in range(n)])
    return result

N = 10
Y_0 = 0
X_0 = 10001000/ 10**7
BETA = 60000/ 10 **7
ALPHA = 0.9
cal(N, Y_0, X_0, BETA, ALPHA)

print("close form", cal_closeform(N, Y_0, X_0, BETA, ALPHA))
# 65132178



# https://www.derivative-calculator.net/
# B = (1-a^x)/(1-a)
# C = x * (1-a^x)/(1-a) - (a - a^x)/(1-a)^2 + (x-1)/(1-a)*a^x
# Y = a^x y_0 + (1-a^x)/(1-a) x_0 + \beta *(x * (1-a^x)/(1-a) - (a - a^x)/(1-a)^2 + (x-1)/(1-a)*a^x)

# max/min = 1/ln(a) * ln(((a-1) * \beta)/((a^2 - 2 a + 1) ln(a) y_0 + (a-1) ln(a) x + a\beta ln(a)