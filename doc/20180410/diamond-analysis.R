#' ---
#' title: "Sarah Gets a Diamond"
#' author: "Dang Trinh - April 11, 2018"  
#' output: 
#'   github_document: 
#'     toc: true
#'     toc_depth: 3
#' ---

#+ setup, include=FALSE
knitr::opts_chunk$set(echo = TRUE, cache = TRUE, warning = FALSE, message = FALSE)


#' # Environment Setup
#' 
#' R is an open source programming language that allows users to extend R by writing 
#' "packages". These packages usually perform a very complex and specific set of 
#' functions that we would like to utilize in our script. For example, the **gbm** 
#' package allows us to fit boosted tree predictive models. 
#' 
#' You can load a package by using the `library()` function as shown below, but you 
#' must first install the package. You can install a package by using the `install.packages()` 
#' function like so:

#+ install-packages, eval=FALSE
install.packages("gbm")


#' After installing all of the packages listed below, then load them up by running 
#' this block of code. It is always a good idea to load all the required packages 
#' at the beginning of your script so that others can know what packages they need 
#' to replicate your analysis.

#+ load-packages
options(scipen=999, digits=6)
library(here)
library(Lahman)
library(lubridate)
library(forecast)
library(dplyr)
library(tidyr)
library(zoo)
library(glmnet)
library(tseries)
library(rpart)
library(rpart.plot)
library(glmnet)
library(forecast)
library(MASS)
library(randomForest)
library(gbm)
#library(prophet)
#library(vars)
#library(tree)


#+ create-output-folder
# create a folder to save our analyses, underlying data
todays_date_formatted <- format(Sys.Date(), '%Y%m%d')
dir.create(here::here('output', todays_date_formatted), showWarnings = FALSE)


#' # Data Wrangling
#' 
#' Data is usually not in a format that is ready for analysis, so we go through a number 
#' of steps that shape the data into a format that R can use for running analysis. We 
#' first read in the data and explore the various variables. The dataset contains 
#' several key attributes of diamond: carat, cut, color, clarity, polish, and symmetry. 
#' The `summary()` gives a quick idea of what they data entails.

#+ load-data
# read the data from github
data_url <- 'https://raw.githubusercontent.com/DardenDSC/sarah-gets-a-diamond/master/data/sarah-gets-a-diamond-raw-data.csv'
raw_diamond_dat <- read.csv(data_url)

# get a sense for what the data entails
summary(raw_diamond_dat)


#' To facilitate subsequent regressions, we will do a minor cleaning of the `cut`
#' variable to remove the space and the hyphen in its values ("Signature-Ideal" and 
#' "Very Good"). We will also create a log transformation and a reciprocal of Carat 
#' Weight and several bins variables for Carat Weight. These bin values were determined 
#' based on a subsequent scatter plot between price and carat weight.

#+ prepare-variables-for-modeling
# create a new variable to keep the raw data separate
diamond <- raw_diamond_dat

diamond <- diamond %>%
  mutate(Clarity = as.factor(Clarity), 
         Dataset = as.factor(Dataset), 
         Cut = as.factor(ifelse(Cut == "Signature-Ideal",
                                "SignatureIdeal", 
                                as.character(Cut))),
         Cut = as.factor(ifelse(Cut == "Very Good", 
                                "VeryGood", 
                                as.character(Cut))),
         LPrice = log(Price),
         LCarat = log(Carat.Weight),
         recipCarat = 1 / Carat.Weight,
         Caratbelow1 = as.numeric(Carat.Weight < 1),
         Caratequal1 = as.numeric(Carat.Weight == 1),
         Caratbelow1.5 = as.numeric((Carat.Weight > 1) & (Carat.Weight < 1.5)),
         Caratequal1.5 = as.numeric(Carat.Weight == 1.5),
         Caratbelow2 = as.numeric((Carat.Weight > 1.5) & (Carat.Weight < 2)),
         Caratabove2 = as.numeric(Carat.Weight >= 2))

summary(diamond)


#' Here we will create several dummy variables, interaction terms, and split the 
#' data into the training and test set. The process of creating additional variables 
#' for analysis is typically referred to as "feature engineering". Feature engineering 
#' helps to find more nuanced relationships and usually leads to improved accuracy in 
#' predictive models

#+ 
dummies <- model.matrix(~ 0 + Cut + Color + Clarity + Polish + Symmetry + Report + 
                              Cut:Color + Cut:Clarity + Cut:Polish + Cut:Symmetry + Cut:Report +
                              Color:Clarity + Color:Polish + Color:Symmetry + Color:Report+
                              Polish:Symmetry + Polish:Report + Symmetry:Report, 
                        data = diamond)

diamond.full <- as.data.frame(cbind(diamond, dummies))

diamond.train <- diamond[diamond$Dataset == "Train",]
diamond.test <- diamond[diamond$Dataset == "Test",]

diamond.full.train <- diamond.full[diamond.full$Dataset == "Train",]
diamond.full.test <- diamond.full[diamond.full$Dataset == "Test",]


#' We will also split the data into a smaller training set and a validation set.

#+ 
nTrain <- dim(diamond.train)[1]
(nSmallTrain <- round(nrow(diamond.train) * 0.75))
(nValid <- nTrain - nSmallTrain)

rowIndicesSmallerTrain <- sample(1:nTrain, size = nSmallTrain, replace = FALSE)

diamond.smaller.train <- diamond.train[rowIndicesSmallerTrain, ]
diamond.validation <- diamond.train[-rowIndicesSmallerTrain, ]

diamond.full.smaller.train <- diamond.full.train[rowIndicesSmallerTrain, ]
diamond.full.validation <- diamond.full.train[-rowIndicesSmallerTrain, ]


#' # Data Visualization
#' 
#' An initial scatterplot of the Price vs. Carat Weight shows that Carat Weight typically 
#' falls into distinct buckets, and that there are significant heteroskedasticity in 
#' the relationship. 

#+ plot-carat-and-price
plot(x=diamond$Carat.Weight, y=diamond$Price, 
     main="Price vs. Carat", 
     ylab="Price", xlab="Carat")


#' Our second scatterplot of the Log Price vs. Carat Weight shows a quadratic relationship. 
#' Furthermore, the heteroskedasticity issue is now fixed.

#+ plot-carat-and-log-price
plot(x=diamond$Carat.Weight, y=diamond$LPrice, 
     main="Log Price vs. Carat", 
     ylab="Log Price", xlab="Carat")


#' Finally, our last scatterplot of Log Price vs. Log Carat Weight shows a linear 
#' relationship with little heteroskedasticity. We will adopt this equation for our 
#' model. For more visualization, see the posted Tableau file.
#' 
#' Note that I currently encounter the IOPub data rate exceeded error below so the 
#' chart does not show up in the output. The tableau file does have the chart though.

#+ plot-log-carat-and-log-price
plot(x=diamond$LCarat, y=diamond$LPrice, 
     main="Log Price vs. Log Carat", 
     ylab="Log Price", xlab="Log Carat")


#' # Building Predictive Models
#' 
#' ## Tree-based models
#' 
#' Here we utilize several tree-based model to predict log price of the diamonds 
#' based on several characteristics present in the data.
#' 
#' ### Single Tuned Tree
#' 
#' Our initial tuned tree (best cp is around 0.00000151859) yields a MAPE of 7.0% 
#' when applied to the validation set. The importance variable list shows that log 
#' carat size, inverse of carat size, as well as the bins of carat size are all 
#' quite significant variables in predicting price.
#' 
#' Note that throughout our modeling analysis we will utilize a common model specification 
#' that each process with start with when fitting.

#+ define-common-model-formula
model_formula <- "LPrice ~ LCarat +  recipCarat + Cut + Color + Clarity + Polish + Symmetry + 
                           Report + Caratbelow1 + Caratequal1 + Caratbelow1.5 +
                           Caratequal1.5 + Caratbelow2 + Caratabove2"


#+ autofitting-rpart-tree
rt.auto.cv <- rpart(model_formula, data = diamond.train, 
                    control = rpart.control(cp = 0.000001, xval = 10))  # xval is number of folds in the K-fold cross-validation.
#printcp(rt.auto.cv)  # Print out the cp table of cross-validation errors.

#The R-squared for a regression tree is 1 minus rel error. 
#xerror (or relative cross-validation error where "x" stands for "cross") is a scaled 
#version of overall average of the 5 out-of-sample MSEs across the 5 folds. 
#For the scaling, the MSE's are divided by the "root node error" of 0.091868, 
#which is the variance in the y's. 
#xstd measures the variation in xerror between the folds. nsplit is the number of terminal nodes minus 1.

plotcp(rt.auto.cv)  # The horizontal line in this plot is one standard deviation above 
# the minimum xerror value in the cp table. Because simpler trees are better, 
# the convention is to choose the cp level to the left of the cp level with the 
# minimum xerror that is first above the line. 

# In this case, the minimum xerror is 0.3972833 at row 35 in the cp table.
rt.auto.cv.table <- as.data.frame(rt.auto.cv$cptable)
min(rt.auto.cv.table$xerror)
bestcp <- rt.auto.cv.table$CP[rt.auto.cv.table$xerror==min(rt.auto.cv.table$xerror)]

# According to this analysis using 5-fold cross-validation, setting cp = 0.002869198 is best. 
# Take a look at the resulting 18-terminal-node tree.
rt.tuned.opt.cv <- rpart(model_formula, data = diamond.train, 
                         control = rpart.control(cp = bestcp))
prp(rt.tuned.opt.cv, type = 1, extra = 1)
importance <- as.data.frame(rt.tuned.opt.cv$variable.importance)
importance


#+ rpart-accuracy
rt.tuned.opt.cv.pred <- predict(rt.tuned.opt.cv, diamond.test)
accuracy(exp(rt.tuned.opt.cv.pred), diamond.test$Price)


#' To facilitate some intuition of the variables, here we generate a few simpler trees 
#' than the model above. These trees have much larger cp parameters and as such have 
#' much fewer layers, which aids with interpretability.

#+ fitting-simple-rpart-trees
# fitting four simple trees using different complexity parameters
rt.simple.tree1 <- rpart(model_formula, data = diamond.train, 
                         control = rpart.control(cp = 0.005))
rt.simple.tree2 <- rpart(model_formula, data = diamond.train, 
                         control = rpart.control(cp = 0.001))
rt.simple.tree3 <- rpart(model_formula, data = diamond.train, 
                         control = rpart.control(cp = 0.0005))
rt.simple.tree4 <- rpart(model_formula, data = diamond.train, 
                         control = rpart.control(cp = 0.0001))


#' Plots of the trees and diagnostics are available in the `output` folder of this analysis.

#+ saving-off-rpart-data-and-pdfs, include=FALSE
write.csv(rt.tuned.opt.cv.pred, 
          file=here::here("output", todays_date_formatted, 
                          sprintf("k-fold-optim-cp-reg-tree_%s.csv", todays_date_formatted)))
write.csv(importance, 
          file=here::here("output", todays_date_formatted, 
                          sprintf("k-fold-optim-cp-reg-tree-var-imp_%s.csv", todays_date_formatted)))

this_filename <- here::here("output", todays_date_formatted, 
                            sprintf("optim-tuned-tree_%s.pdf", todays_date_formatted))
cairo_pdf(file=this_filename, height=8.5, width=11)
prp(rt.tuned.opt.cv, type = 1, extra = 1)
dev.off()

this_filename <- here::here("output", todays_date_formatted, 
                            sprintf("simple-tree-1_%s.pdf", todays_date_formatted))
cairo_pdf(file=this_filename, height=8.5, width=11)
prp(rt.simple.tree1, type = 1, extra = 1)
dev.off()

this_filename <- here::here("output", todays_date_formatted, 
                            sprintf("simple-tree-2_%s.pdf", todays_date_formatted))
cairo_pdf(file=this_filename, height=8.5, width=11)
prp(rt.simple.tree2, type = 1, extra = 1)
dev.off()

this_filename <- here::here("output", todays_date_formatted, 
                            sprintf("simple-tree-3_%s.pdf", todays_date_formatted))
cairo_pdf(file=this_filename, height=8.5, width=11)
prp(rt.simple.tree3, type = 1, extra = 1)
dev.off()

this_filename <- here::here("output", todays_date_formatted, 
                            sprintf("simple-tree-4_%s.pdf", todays_date_formatted))
cairo_pdf(file=this_filename, height=8.5, width=11)
prp(rt.simple.tree4, type = 1, extra = 1)
dev.off()


#' ### Bagged Tree
#' 
#' The second tree-based method is a bagged tree, which we implement with the `randomForest()` 
#' function and the `mtry` argument set equal to 5 - the number of explanatory 
#' variables feed into the model.

#+  bagged-tree-on-train-dataset
#bag with smaller train dataset#
bag.tree <- randomForest(as.formula(model_formula), 
                         data=diamond.smaller.train, mtry=5, ntree=100,
                         importance=TRUE)
bag.tree.pred.valid <- predict(bag.tree, newdata=diamond.validation)
accuracy(exp(bag.tree.pred.valid), diamond.validation$Price)


#' This bagged tree yields a MAPE of 5.57% on the validation set, already a great 
#' improvement from the 7.0% of the single tuned tree. Given the improvement of the 
#' bagged tree, we could estimate the bagged tree on the full training set by feeding 
#' that dataset to the `randomForest()` function like so:

#+ bagged-tree-on-full-dataset, eval=FALSE
bag.tree <- randomForest(as.formula(model_formula), 
                         data=diamond.train, mtry=5, ntree=100,
                         importance=TRUE)


#' ### Random Forest
#' 
#' The third tree-based model we implement is a cross validated random forest, which 
#' decorrelates the tree and should provide additional improvements over the bagged 
#' tree method.

#+ prepare-data-for-rf-cv-training
# k-folds cross validation automatically using rfcv
trainx <- diamond.smaller.train[,c("LCarat", "recipCarat", "Cut", "Color", "Clarity", "Polish", "Symmetry",
                                  "Report", "Caratbelow1", "Caratequal1", "Caratbelow1.5","Caratequal1.5", 
                                  "Caratbelow2", "Caratabove2")]
trainy <- diamond.smaller.train$LPrice
random.forest.cv <- rfcv(trainx, trainy,
                         cv.folds = 10, scale="unit", step=-1, ntree=100)
plot(x=1:14, y=rev(random.forest.cv$error.cv),
     xlab="mtry parameter", ylab="Cross Validation Error",
     main="Random Forest Cross Validation Results")


#' The cross validation results above shows that the best number of `mtry` for random 
#' forest should be 9 (vs. 14). We will use this value when estimating our random 
#' forest model.

#+ check-best-rf-cv-error
random.forest.cv$error.cv[random.forest.cv$error.cv==min(random.forest.cv$error.cv)]


#+ fit-the-final-rf-model
random.forest.cv.1 <- randomForest(as.formula(model_formula), 
                                   data=diamond.smaller.train, mtry=9, ntree=100,
                                   importance=TRUE)
random.forest.cv.1.pred.valid <- predict(random.forest.cv.1, newdata=diamond.validation)
accuracy(exp(random.forest.cv.1.pred.valid), diamond.validation$Price)


#' Finally, we can repeat the same procedures above on the full training set.

#+  eval=FALSE
# perform cross validation to tune the model parameters
trainx <- diamond.train[,c("LCarat", "recipCarat", "Cut", "Color", "Clarity", "Polish", "Symmetry",
                           "Report", "Caratbelow1", "Caratequal1", "Caratbelow1.5","Caratequal1.5", 
                           "Caratbelow2", "Caratabove2")]
trainy <- diamond.train$LPrice
random.forest.cv <- rfcv(trainx, 
                         trainy,
                         cv.folds=10, scale="unit", step=-1, ntree=100)

# determine the best fitting model
random.forest.cv$error.cv
length(random.forest.cv$error.cv)
plot(x=1:14, y=rev(random.forest.cv$error.cv),
     xlab="mtry parameter", ylab="Cross Validation Error",
     main="Random Forest Cross Validation Results")
random.forest.cv$error.cv[random.forest.cv$error.cv==min(random.forest.cv$error.cv)]

# use the optimal parameters to fit the final model
random.forest.cv.1 <- randomForest(as.formula(model_formula), 
                                   data=diamond.train, mtry=9, ntree=100,
                                   importance=TRUE)
# measure the accuracy
random.forest.cv.1.pred <- predict(random.forest.cv.1, newdata=diamond.test)
accuracy(exp(random.forest.cv.1.pred), diamond.test$Price)


#' ### Boosted Trees
#' 
#' The last tree-based model we will be using is a boosted tree model. We use cross 
#' validation to identify the best value for the parameter `n.trees`, which turns out 
#' to be 5,207.

#+ 
boost <- gbm(as.formula(model_formula), data=diamond.smaller.train,
             distribution = "gaussian",
             n.trees=100, interaction.depth=6, cv.folds=10, shrinkage = 0.011)
plot(boost$cv.error)
best_iteration <- which(boost$cv.error==min(boost$cv.error))


#' Using this `n.trees` parameter, we estimate the model on the smaller training set using 
#' 100 iterations, which yields a MAPE of 4.46% on the validation set, representing additional 
#' improvements over the random forest model. It looks like the model is continually getting 
#' better even at the 100th iteration. More iterations might help us find the true 
#' optimum number of trees to minimize prediction error.

#+ 
boost.cv <- gbm(as.formula(model_formula), data=diamond.smaller.train,
                distribution = "gaussian",
                n.trees=best_iteration, interaction.depth=6, cv.folds=10, shrinkage = 0.011)
boost.cv.pred.valid <- predict(boost.cv, newdata=diamond.validation, n.trees=best_iteration)
accuracy(exp(boost.cv.pred.valid), diamond.validation$Price)


#' Finally, we repeat the same procedures above using the full dataset, including 
#' cross validation. Cross validation shows that 100 is the best value for `n.trees`, 
#' and using this parameter yields a MAPE of 4.23808% on the test set.

#+  eval=FALSE
boost <- gbm(as.formula(model_formula), data=diamond.train,
             distribution = "gaussian",
             n.trees=100, interaction.depth=6, cv.folds=10, shrinkage = 0.011)
best_iteration <- which(boost$cv.error==min(boost$cv.error))
boost.cv <- gbm(as.formula(model_formula), data=diamond.train,
                distribution = "gaussian",
                n.trees=best_iteration, interaction.depth=6, cv.folds=10, shrinkage = 0.011)
boost.cv.pred <- predict(boost.cv, newdata=diamond.test, n.trees=best_iteration)
accuracy(exp(boost.cv.pred), diamond.test$Price)


#' ## Regression Models
#' 
#' Another class of model we could use is linear regression model. In this section 
#' we will use several approaches to calibrate our linear regression model.
#' 
#' ### Backward Step-Wise Linear Regression
#' 
#' We start by including all categorical variables & possible interactions in our 
#' linear model. This yields a MAPE of 5.34222% on the validation set.

#+ define-lm-formula
lm_formula <- "LPrice ~ LCarat+recipCarat+Caratbelow1+Caratequal1+Caratbelow1.5+Caratequal1.5+Caratbelow2+Caratabove2+CutFair+CutGood+CutIdeal+CutSignatureIdeal+CutVeryGood+ColorE+ColorF+ColorG+ColorH+ColorI+ClarityIF+ClaritySI1+ClarityVS1+ClarityVS2+ClarityVVS1+ClarityVVS2+PolishG+PolishID+PolishVG+SymmetryG+SymmetryID+SymmetryVG+ReportGIA+CutGood:ColorE+CutIdeal:ColorE+CutSignatureIdeal:ColorE+CutVeryGood:ColorE+CutGood:ColorF+CutIdeal:ColorF+CutSignatureIdeal:ColorF+CutVeryGood:ColorF+CutGood:ColorG+CutIdeal:ColorG+CutSignatureIdeal:ColorG+CutVeryGood:ColorG+CutGood:ColorH+CutIdeal:ColorH+CutSignatureIdeal:ColorH+CutVeryGood:ColorH+CutGood:ColorI+CutIdeal:ColorI+CutSignatureIdeal:ColorI+CutVeryGood:ColorI+CutGood:ClarityIF+CutIdeal:ClarityIF+CutSignatureIdeal:ClarityIF+CutVeryGood:ClarityIF+CutGood:ClaritySI1+CutIdeal:ClaritySI1+CutSignatureIdeal:ClaritySI1+CutVeryGood:ClaritySI1+CutGood:ClarityVS1+CutIdeal:ClarityVS1+CutSignatureIdeal:ClarityVS1+CutVeryGood:ClarityVS1+CutGood:ClarityVS2+CutIdeal:ClarityVS2+CutSignatureIdeal:ClarityVS2+CutVeryGood:ClarityVS2+CutGood:ClarityVVS1+CutIdeal:ClarityVVS1+CutSignatureIdeal:ClarityVVS1+CutVeryGood:ClarityVVS1+CutGood:ClarityVVS2+CutIdeal:ClarityVVS2+CutSignatureIdeal:ClarityVVS2+CutVeryGood:ClarityVVS2+CutGood:PolishG+CutIdeal:PolishG+CutSignatureIdeal:PolishG+CutVeryGood:PolishG+CutGood:PolishID+CutIdeal:PolishID+CutSignatureIdeal:PolishID+CutVeryGood:PolishID+CutGood:PolishVG+CutIdeal:PolishVG+CutSignatureIdeal:PolishVG+CutVeryGood:PolishVG+CutGood:SymmetryG+CutIdeal:SymmetryG+CutSignatureIdeal:SymmetryG+CutVeryGood:SymmetryG+CutGood:SymmetryID+CutIdeal:SymmetryID+CutSignatureIdeal:SymmetryID+CutVeryGood:SymmetryID+CutGood:SymmetryVG+CutIdeal:SymmetryVG+CutSignatureIdeal:SymmetryVG+CutVeryGood:SymmetryVG+CutGood:ReportGIA+CutIdeal:ReportGIA+CutSignatureIdeal:ReportGIA+CutVeryGood:ReportGIA+ColorE:ClarityIF+ColorF:ClarityIF+ColorG:ClarityIF+ColorH:ClarityIF+ColorI:ClarityIF+ColorE:ClaritySI1+ColorF:ClaritySI1+ColorG:ClaritySI1+ColorH:ClaritySI1+ColorI:ClaritySI1+ColorE:ClarityVS1+ColorF:ClarityVS1+ColorG:ClarityVS1+ColorH:ClarityVS1+ColorI:ClarityVS1+ColorE:ClarityVS2+ColorF:ClarityVS2+ColorG:ClarityVS2+ColorH:ClarityVS2+ColorI:ClarityVS2+ColorE:ClarityVVS1+ColorF:ClarityVVS1+ColorG:ClarityVVS1+ColorH:ClarityVVS1+ColorI:ClarityVVS1+ColorE:ClarityVVS2+ColorF:ClarityVVS2+ColorG:ClarityVVS2+ColorH:ClarityVVS2+ColorI:ClarityVVS2+ColorE:PolishG+ColorF:PolishG+ColorG:PolishG+ColorH:PolishG+ColorI:PolishG+ColorE:PolishID+ColorF:PolishID+ColorG:PolishID+ColorH:PolishID+ColorI:PolishID+ColorE:PolishVG+ColorF:PolishVG+ColorG:PolishVG+ColorH:PolishVG+ColorI:PolishVG+ColorE:SymmetryG+ColorF:SymmetryG+ColorG:SymmetryG+ColorH:SymmetryG+ColorI:SymmetryG+ColorE:SymmetryID+ColorF:SymmetryID+ColorG:SymmetryID+ColorH:SymmetryID+ColorI:SymmetryID+ColorE:SymmetryVG+ColorF:SymmetryVG+ColorG:SymmetryVG+ColorH:SymmetryVG+ColorI:SymmetryVG+ColorE:ReportGIA+ColorF:ReportGIA+ColorG:ReportGIA+ColorH:ReportGIA+ColorI:ReportGIA+PolishG:SymmetryG+PolishID:SymmetryG+PolishVG:SymmetryG+PolishG:SymmetryID+PolishID:SymmetryID+PolishVG:SymmetryID+PolishG:SymmetryVG+PolishID:SymmetryVG+PolishVG:SymmetryVG+PolishG:ReportGIA+PolishID:ReportGIA+PolishVG:ReportGIA+SymmetryG:ReportGIA+SymmetryID:ReportGIA+SymmetryVG:ReportGIA
          + LCarat:Cut + LCarat:Color + LCarat:Calarity + LCarat:Polish + LCarat:Symmetry + LCarat:Report
          + Caratbelow1:Cut + Caratbelow1:Color + Caratbelow1:Calarity + 
            Caratbelow1:Polish + Caratbelow1:Symmetry + Caratbelow1:Report"


#+ fit-lm
lm <- lm(as.formula(lm_formula), data = diamond.full.smaller.train)
summary(lm)


#+ eval-lm-model
lm.pred.valid <- predict(lm, diamond.full.validation)
accuracy(exp(lm.pred.valid), diamond.full.validation$Price)


#' Here we will perform the step-wise backward regression by doing at most 
#' 10 steps to weed out the variables that are not considered significant. More 
#' steps may be needed to find the optimum model. The argument `trace=0` means that 
#' the diagnostics of each step are not printed to the screen.

#+ perform-stepwise-regression
lm.step <- step(lm, direction = "backward", trace=0, step=10)
lm.step.pred <- predict(lm.step, diamond.full.test)
accuracy(exp(lm.step.pred), diamond.full.test$Price)


#' ### Lasso Regression
#' 
#' Another method we could use to choose which variable to include is the Lasso regression. 
#' Here we use cross-validation to determine the best lambda parameter used in Lasso 
#' regression to "regularize" the coefficients of the variables included. 

#+ fit-lass0
#smaller train dataset
xtrain <- as.matrix(diamond.full.smaller.train[, -c(1:11)])
ytrain <- as.vector(diamond.full.smaller.train$LPrice)
xtest <- as.matrix(diamond.full.validation[, -c(1:11)])
lm.regularized.cv <- cv.glmnet(xtrain, ytrain, 
                               nfolds = 10, family = "gaussian", alpha=1)


#+ 
lm.regularized.cv$lambda.min
(minLogLambda <- log(lm.regularized.cv$lambda.min))
coef(lm.regularized.cv, s = "lambda.min")  
plot(lm.regularized.cv, label = TRUE)
abline(v = minLogLambda)


#+ 
lm.regularized <- glmnet(xtrain, ytrain, family = "gaussian", 
                         lambda=lm.regularized.cv$lambda.min)
plot(lm.regularized, xvar = "lambda", label = TRUE)


#+ 
lm.regularized.cv.pred.valid <- predict(lm.regularized.cv, newx = xtest, s = "lambda.min") 
lm.regularized.pred.valid <- predict(lm.regularized, newx = xtest, s = "lambda.min") 


#+ 
accuracy(exp(as.ts(lm.regularized.cv.pred.valid)), as.ts(diamond.full.validation$Price))
accuracy(exp(as.ts(lm.regularized.pred.valid)), as.ts(diamond.full.validation$Price))


#+ 
#full dataset
xtrain <- as.matrix(diamond.full.train[, -c(1:11)])
ytrain <- as.vector(diamond.full.train$LPrice)
xtest <- as.matrix(diamond.full.test[, -c(1:11)])
lm.regularized.cv <- cv.glmnet(xtrain, ytrain, 
                               nfolds = 10, family = "gaussian", alpha=1)  # Fits the Lasso.


#+ 
lm.regularized.cv$lambda.min
(minLogLambda <- log(lm.regularized.cv$lambda.min))
coef(lm.regularized.cv, s = "lambda.min")  
plot(lm.regularized.cv, label = TRUE)
abline(v = minLogLambda)


#+ 
lm.regularized <- glmnet(xtrain, ytrain, family = "gaussian", 
                         lambda=lm.regularized.cv$lambda.min)
plot(lm.regularized, xvar = "lambda", label = TRUE)


#+ 
lm.regularized.cv.pred <- predict(lm.regularized.cv, newx = xtest, s = "lambda.min") 
lm.regularized.pred <- predict(lm.regularized, newx = xtest, s = "lambda.min") 
head(lm.regularized.cv.pred)
head(lm.regularized.pred)
head(as.numeric(exp(lm.regularized.cv.pred)))
head(as.numeric(diamond.full.validation$Price))
accuracy(as.numeric(exp(lm.regularized.cv.pred)), as.numeric(diamond.full.test$Price))
accuracy(as.numeric(exp(lm.regularized.pred)), as.numeric(diamond.full.test$Price))


#' ## Ensemble Forecasts
#' 
#' Among the methods above, we have identified a few models that yield MAPE less 
#' than 11% on the validation set. 

#+ 
accuracy((exp(bag.tree.pred.valid)), diamond.full.validation$Price)
accuracy((exp(random.forest.cv.1.pred.valid)), diamond.full.validation$Price)
accuracy((exp(boost.cv.pred.valid)), diamond.full.validation$Price)
accuracy((exp(lm.pred.valid)), diamond.full.validation$Price)
accuracy((exp(lm.step.pred)), diamond.full.validation$Price)
accuracy(as.numeric((exp(lm.regularized.pred.valid))), diamond.full.validation$Price)


#+ 
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid))/2, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(boost.cv.pred.valid))/2, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(lm.pred.valid))/2, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(lm.step.pred))/2, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+as.numeric(exp(lm.regularized.pred.valid)))/2, diamond.full.validation$Price)


#+ 
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(boost.cv.pred.valid))/2, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(lm.pred.valid))/2, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(lm.step.pred))/2, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+as.numeric(exp(lm.regularized.pred.valid)))/2, diamond.full.validation$Price)


#+ 
accuracy(((exp(boost.cv.pred.valid))+exp(lm.pred.valid))/2, diamond.full.validation$Price)
accuracy(((exp(boost.cv.pred.valid))+exp(lm.step.pred))/2, diamond.full.validation$Price)
accuracy(((exp(boost.cv.pred.valid))+as.numeric(exp(lm.regularized.pred.valid)))/2, diamond.full.validation$Price)


#+ 
accuracy(((exp(lm.pred.valid))+exp(lm.step.pred))/2, diamond.full.validation$Price)
accuracy(((exp(lm.pred.valid))+as.numeric(exp(lm.regularized.pred.valid)))/2, diamond.full.validation$Price)
accuracy(((exp(lm.step.pred))+as.numeric(exp(lm.regularized.pred.valid)))/2, diamond.full.validation$Price)


#+ 
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(boost.cv.pred.valid))/3, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(lm.pred.valid))/3, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(lm.step.pred))/3, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)


#+ 
accuracy(((exp(bag.tree.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.pred.valid))/3, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.step.pred))/3, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(boost.cv.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)


#+ 
accuracy(((exp(bag.tree.pred.valid))+exp(lm.pred.valid)+exp(lm.step.pred))/3, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(lm.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)


#+ 
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.pred.valid))/3, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.step.pred))/3, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(boost.cv.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)


#+ 
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(lm.pred.valid)+exp(lm.step.pred))/3, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(lm.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)


#+ 
accuracy(((exp(boost.cv.pred.valid))+exp(lm.pred.valid)+exp(lm.step.pred))/3, diamond.full.validation$Price)
accuracy(((exp(boost.cv.pred.valid))+exp(lm.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)
accuracy(((exp(boost.cv.pred.valid))+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)
accuracy(((exp(lm.pred.valid))+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/3, diamond.full.validation$Price)


#+ 
head(((exp(random.forest.cv.1.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.pred.valid))/3)
head((exp(random.forest.cv.1.pred.valid)))


#+ 
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(boost.cv.pred.valid)+exp(lm.pred.valid))/4, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(boost.cv.pred.valid)+exp(lm.step.pred))/4, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(boost.cv.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)

accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(lm.pred.valid)+exp(lm.step.pred))/4, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(lm.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)


#+ 
accuracy(((exp(bag.tree.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.pred.valid)+exp(lm.step.pred))/4, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(lm.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)


#+ 
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.pred.valid)+exp(lm.step.pred))/4, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(lm.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)
accuracy(((exp(boost.cv.pred.valid))+exp(lm.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/4, diamond.full.validation$Price)


#+ 
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(boost.cv.pred.valid)+exp(lm.pred.valid)+as.numeric(exp(lm.step.pred)))/5, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(boost.cv.pred.valid)+exp(lm.pred.valid)+as.numeric(exp(lm.regularized.pred.valid)))/5, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(boost.cv.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/5, diamond.full.validation$Price)

accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(lm.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/5, diamond.full.validation$Price)
accuracy(((exp(bag.tree.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/5, diamond.full.validation$Price)
accuracy(((exp(random.forest.cv.1.pred.valid))+exp(boost.cv.pred.valid)+exp(lm.pred.valid)+exp(lm.step.pred)+as.numeric(exp(lm.regularized.pred.valid)))/5, diamond.full.validation$Price)


#+ 
accuracy(((exp(bag.tree.pred.valid))+exp(random.forest.cv.1.pred.valid)+exp(boost.cv.pred.valid)+exp(lm.pred.valid)+as.numeric(exp(lm.step.pred))+as.numeric(exp(lm.regularized.pred.valid)))/6, diamond.full.validation$Price)


#' # Summary of Analysis & Areas for Further Research
#' 
#' A few key conclusions are worth noting after our analysis of the data:
#' 
#' (1) Best model for predicting diamond prices is a boosted tree model, which gives MAPE of 4.23%
#' 
#' (2) Given the scatter plot between price and carat weight, the log-log relationship makes the most sense
#' 
#' (3) Although we include log(carat weight) and 1/carat weight as explanatory variables, there seem to be distinct clusters of prices based on ranges of carat weights, as the bin dummies based on carat weight we created were m
#' 
#' (4) Though tree-based models tend to outperform linear regression models, they lose out on model intepretability. In particular, it is a lot easier to get an estimate of the marginal effect of a specific attribute on diamond price with a linear regression model vs. a tree-based model.
#' 
#' (5) That said, using a tree-based model to help determine which variables and interaction terms to include as a start in a linear regression appears to be fruitful.
